# lemonade-sdk's local AI server: OpenAI/Ollama/Anthropic-compatible REST API
# on localhost, a web UI, a CLI and the Tauri desktop app, orchestrating
# llama.cpp / whisper.cpp / stable-diffusion.cpp backends it manages itself.
#
# The packaging comes from nix-amd-ai, whose primary target is Ryzen AI (XDNA
# NPU + ROCm iGPU), so the NPU and ROCm halves are switched off here. What is
# left is lemonade's CUDA backend driving the 3090, with Vulkan kept on for
# the whisper/sd recipes that have no CUDA variant in this packaging.
{ den, inputs, ... }:
{
  den.aspects.lemonade.nixos =
    { config, pkgs, ... }:
    let
      # Stable /etc indirection, matching what the module does for its own
      # backends: lemond caches the bin path in ~/.cache/lemonade/config.json,
      # so a raw /nix/store path would dangle after a rebuild + GC. The symlink
      # retargets each generation and the cached path stays valid.
      cudaBin = "/etc/lemonade/backends/llamacpp-cuda";

      # lemonade-app's WebKitGTK view crashes instantly on launch under
      # Hyprland ("Gdk-Message: Error 71 (Protocol error) dispatching to
      # Wayland display", exit 1, no window ever shown): WebKitGTK's
      # linux-dmabuf compositing path trips a Wayland protocol error on this
      # compositor. WEBKIT_DISABLE_DMABUF_RENDERER=1 avoids it - but setting
      # only environment.sessionVariables is not enough to actually deliver
      # it: that only lands in /etc/pam/environment, and this greetd+Hyprland
      # session never routes PAM's environment into either the compositor's
      # or systemd --user's environment (confirmed via
      # `systemctl --user show-environment`, which lacks the var even right
      # after a clean boot). So the app still launches without it and still
      # crashes regardless of the sessionVariables line below.
      #
      # Bake the var into the launched binary instead. `pkgs.lemonade`'s own
      # bin/lemonade-app is a compiled makeBinaryWrapper stub (wrapGAppsHook3),
      # which refuses to be wrapped a second time (`wrapProgram` aborts if the
      # hidden `.lemonade-app-wrapped` path already exists) - and amd-npu.nix
      # builds its installed copy via `pkgs.lemonade.override { ... }`, which
      # re-invokes the original function and would silently drop an
      # `overrideAttrs` patch anyway. Simplest path that survives both: a tiny
      # separate package that execs the real wrapper with the var set, given
      # `hiPrio` so it wins the bin/lemonade-app collision in
      # environment.systemPackages's buildEnv over amd-npu.nix's own copy.
      lemonadeAppWebkitFix = pkgs.lib.hiPrio (
        pkgs.runCommand "lemonade-app-webkit-fix" { } ''
          mkdir -p "$out/bin"
          cat > "$out/bin/lemonade-app" <<'WRAPPER_EOF'
          #!${pkgs.runtimeShell}
          export WEBKIT_DISABLE_DMABUF_RENDERER=1
          exec -a lemonade-app ${pkgs.lemonade}/bin/lemonade-app "$@"
          WRAPPER_EOF
          chmod +x "$out/bin/lemonade-app"
        ''
      );

      # lemond's MCP client host (stdio transport only) reads its server list
      # from mcp_servers.json in the cache dir, sitting next to config.json.
      # There's no LEMONADE_*_PATH seed hook for it like there is for
      # config.json, so this is reconciled by hand below, same shape as
      # nix-amd-ai's own lemond-reconcile-config: merge Nix-declared servers
      # over whatever's already there on every start, so entries added live
      # via the UI/`/internal/mcp/servers` survive a rebuild.
      mcpServers = {
        # "example" = {
        #   command = "npx";
        #   args = [ "-y" "@some-org/mcp-server-name" ];
        #   env = { };
        # };
      };

      mcpServersFile = (pkgs.formats.json { }).generate "mcp_servers.json" {
        inherit mcpServers;
      };

      mcpServersReconcile = pkgs.writeShellApplication {
        name = "lemond-reconcile-mcp";
        runtimeInputs = [
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          servers="''${LEMONADE_CACHE_DIR:-''${HOME:-}/.cache/lemonade}/mcp_servers.json"
          mkdir -p "$(dirname "$servers")"
          [ -f "$servers" ] || echo '{}' > "$servers"

          tmp="$servers.nix-reconcile"
          if jq -s '.[0] * .[1]' "$servers" ${mcpServersFile} >"$tmp"; then
            mv "$tmp" "$servers"
          else
            rm -f "$tmp"
            echo "lemond: $servers is unreadable, leaving it untouched" >&2
          fi
        '';
      };

      # Weights live here for every tool that wants them; also fed to
      # lemonade.settings.extra_models_dir below, and to the draft-model paths
      # in recipeOptions, so the location is stated once.
      modelsDir = "/mnt/games/models";

      # Per-model llama-server tuning, reconciled exactly like mcp_servers.json
      # above.
      #
      # lemond reads recipe_options.json ONCE, at startup. A live edit to the
      # file is ignored - GET /api/v1/models keeps reporting the stale
      # recipe_options ({} for a model that has never had any) and the launched
      # llama-server keeps the old flags - so this is an ExecStartPre reconcile
      # rather than a poke at the API, and every change here needs a lemond
      # restart before it does anything.
      #
      # These entries are not optional. Without one, a model launches on
      # lemonade's defaults: --ctx-size <the model's own maximum> and an
      # unquantized KV cache. Measured on this box, that made the 2.8 GB
      # Qwen3.5-4B take 13,820 MiB of VRAM (it launched with --ctx-size
      # 262144). Anything that should be loadable on a 24 GiB card needs an
      # explicit ctx_size and KV quantization here.
      #
      # Keys are "<source>.<model id>", where the id is the leaf DIRECTORY name
      # under extra_models_dir - NOT the GGUF filename. Renaming a model
      # directory silently orphans its entry. "extra" prefixes extra_models_dir
      # models; lemonade's own registry uses "builtin".
      #
      # merge_args keeps lemonade's computed flags (backend selection, --jinja,
      # --metrics, --reasoning-format, and its MTP autodetection) and layers
      # these over them. ctx_size is what becomes --ctx-size, so -c/--ctx-size
      # must never appear in llamacpp_args: lemonade refuses to launch at all
      # on an argument it manages itself, logging "Invalid custom llama-server
      # arguments" and failing the load.
      #
      # Models absent from this set keep whatever the file already holds - the
      # merge is per-key - which is what leaves an entry like
      # "extra.unsloth-iq4nl" (the IQ4_NL quant of Qwen3.8-27B) untouched.
      # The corollary is that a deleted model's entry is NOT cleaned up
      # automatically; gemma-4-12b's was removed by hand when its weights were
      # deleted on 2026-08-20.
      #
      # Verified against the running lemond (2026-08-20) by setting the global
      # llamacpp.args over /internal/set, loading a model, and reading
      # /proc/<llama-server pid>/cmdline - the only place the merged result is
      # visible. Results, which the entries below depend on:
      #   - --reasoning-budget passes the reserved-argument check and reaches
      #     llama-server intact.
      #   - --cache-type-k/--cache-type-v pass.
      #   - a flag lemonade also computes is REPLACED, not duplicated: passing
      #     --spec-draft-n-max 2 removed lemonade's own --spec-draft-n-max 3
      #     from the command line, while its --spec-type draft-mtp and
      #     --spec-draft-p-min 0.75 (not overridden) survived. This is what
      #     makes overriding lemonade's MTP autodetect defaults work.
      #
      # The reserved list itself, as lemonade reports it when it refuses a
      # load - everything here is computed by lemonade and must never appear
      # in llamacpp_args:
      #   --ctx-size, --device, --embedding, --embeddings, --jinja, --metrics,
      #   --mmproj, --mmproj-auto, --mmproj-offload, --mmproj-url, --model,
      #   --model-draft, --no-jinja, --no-mmproj, --no-mmproj-auto,
      #   --no-mmproj-offload, --port, --rerank, --reranking,
      #   --spec-draft-model, -c, -dev, -m
      #
      # Note the shape of that list: lemonade reserves the flags that SELECT
      # things (which model, which draft model, which projector, which device,
      # what context) and leaves the flags that TUNE them free. So
      # --spec-draft-n-max and --spec-draft-ngl are ours to set while
      # --model-draft is not, and mmproj pairing is automatic rather than
      # configurable.
      recipeOptions = {
        # Qwen3.8-27B - the flags ported from the hand-started llama-server
        # unit in ai/llama-cpp.nix, which measured 57-62 tok/s at 81-89% MTP
        # draft acceptance. --spec-draft-n-max 2 is the tuned value and is
        # passed explicitly because lemonade's MTP autodetect otherwise
        # defaults it to 3.
        #
        # ctx_size 98304 is this model's own best value, but it CANNOT be
        # loaded at that size while gemma-4-E4B holds the pin. Measured/derived
        # from its GGUF: 65 layers, 16 full-attention at full_attention_interval
        # 4, head_count_kv 4, key/value_length 256 = 2176 B per token per
        # full-attention layer, plus 147 MiB of constant SSM state over the 49
        # recurrent layers. That is 3.33 GiB of KV at 98304 (1.21 GiB at 32768)
        # on top of ~15.3 GiB of weights - roughly 26.5 GiB all-in beside the
        # pinned coordinator, against a 24 GiB card. Even 32768 leaves only
        # ~200 MiB, and 32768 is already tight for Hermes, whose system prompt
        # is ~24k with tool schemas.
        #
        # The value is left correct rather than quietly cut, because the right
        # resolution depends on something still UNVERIFIED: whether lemonade
        # fails the load or evicts the pin under memory pressure. If it evicts,
        # nothing needs changing - the coordinator simply reloads, and 4 GiB
        # reloads fast. If it fails the load, either drop this to 32768 and
        # accept the squeeze, or unpin the coordinator when using this model.
        # Muse Glimmer is the heavy model this design is actually built around.
        #
        # --reasoning-budget is load-bearing rather than cosmetic: Hermes drops
        # agent.reasoning_effort for models it does not recognise and llama.cpp
        # ignores extra_body, so this server flag is the only thing that caps
        # reasoning on this model.
        #
        # No --model-draft, for two reasons. It is RESERVED by lemonade
        # (see the reserved list documented above) and fails the whole load.
        # And it is unnecessary: the main GGUF carries
        # `qwen35.nextn_predict_layers = 1`, i.e. the MTP head is embedded, so
        # lemonade's autodetect enables draft decoding against it with no
        # sidecar - the same path Qwen3.5-4B takes. The separate
        # MTP/mtp-Qwen3.8-27B-Q4_0.gguf that ai/llama-cpp.nix passes explicitly
        # is the extracted copy of that same head, so nothing is lost.
        "extra.unsloth-ud-q4km" = {
          ctx_size = 98304;
          llamacpp_backend = "cuda";
          merge_args = true;
          llamacpp_args = builtins.concatStringsSep " " [
            "--parallel 1"
            "--cache-type-k q8_0 --cache-type-v q8_0"
            "--flash-attn on -b 2048 -ub 512"
            "--reasoning-budget 192"
            "--spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-ngl 99"
          ];
        };

        # Muse Glimmer 30B (Meta, Apache 2.0) - 14.8 GB of weights plus a
        # 1.5 GB DFlash drafter, so ~16.3 GiB resident before the KV cache.
        #
        # ctx_size is the model's full 131072 because its KV cache is
        # remarkably cheap, computed from the GGUF metadata:
        #   head_count_kv = 2 (16:1 GQA against 32 query heads), key/value
        #   length 128, block_count 52, sliding_window 2048 with
        #   sliding_window_pattern 4 - so only every 4th layer (13 of 52) holds
        #   full-context KV; the other 39 never exceed a 2048-token window.
        # At q8_0 that is 2*2*128*1.0625 = 544 B per token per layer:
        #   13 * 544 * 131072  = 884 MiB   (full-attention layers)
        #   39 * 544 * 2048    =  41 MiB   (sliding-window layers, fixed)
        #                        -------
        #                        925 MiB total at maximum context.
        # Weights + drafter + KV + compute buffers land near 17.6 GiB of the
        # ~22 GiB usable once the desktop's share is out, leaving ~4 GiB.
        #
        # Do NOT add --swa-full: it forces full-length KV onto the 39
        # sliding-window layers and would turn that 925 MiB into ~3.6 GiB for
        # no benefit.
        #
        # DFlash speculative decoding is currently OFF, and not by choice.
        # Unlike Qwen3.8-27B, this model has NO embedded draft head (no
        # nextn_predict_layers key); DFlash is a genuinely separate
        # block-diffusion drafter in DFlash/dflash-kquant.gguf. Naming it needs
        # --model-draft, which lemonade reserves and refuses. lemonade's own
        # autodetect only recognises embedded MTP heads, and the scanner
        # registers the DFlash/ subdirectory as a standalone model rather than
        # pairing it as this model's drafter.
        #
        # The unexplored route is registering a user model in
        # ~/.cache/lemonade/user_models.json with an explicit
        # checkpoints.draft alongside checkpoints.main - untested, and the
        # binary's message "Additional checkpoints must contain an exact
        # repository variant" suggests extra checkpoints want HuggingFace refs
        # rather than the local paths these files have.
        #
        # Silver lining: skipping the drafter frees its 1.52 GiB, putting this
        # model at ~16.1 GiB rather than ~17.6 GiB and widening the co-resident
        # budget from ~3.6 GiB to ~5.1 GiB.
        #
        # ── The mmproj is DELIBERATELY NOT NEXT TO THE WEIGHTS ───────────────
        # lemonade's scanner pairs any mmproj-*.gguf sitting in a model's own
        # directory and passes it as --mmproj automatically. For this model
        # that projector is 1335 MiB of VRAM buying a capability nothing here
        # uses: the bots (modules/ai/hermes-bots.nix) are text agents, and the
        # multimodal chat surface is gemma-4-e4b, which has the better
        # projector anyway - vision AND audio, where this one is vision-only.
        #
        # Worse, it was not merely wasted, it was actively costing throughput.
        # lemonade never passes -ngl (no such string exists in the lemond
        # binary), so llama.cpp's own default of `auto` sizes the offload to
        # whatever VRAM is free AT LOAD TIME. gemma is pinned and loads first,
        # so by the time this model loads the projector no longer fits and
        # `auto` silently parks ~2.5 GiB of WEIGHTS on the CPU instead of
        # failing. Measured 2026-08-20, same prompt, same 300 tokens:
        #   projector paired    15.8 tok/s   (15224 MiB, layers on CPU)
        #   projector unpaired  35.1 tok/s   (15698 MiB, 1465 MiB still free)
        # i.e. a 2.2x decode regression that announced itself nowhere.
        #
        # THE FIX IS A FILE MOVE, AND NIX CANNOT SEE IT:
        #   /mnt/games/models/muse-glimmer-30b-gguf/muse-glimmer-30b/
        #     vision-unpaired/mmproj-kquant.gguf
        # It used to sit one level up, beside the weights. It is in a
        # subdirectory purely so the scanner stops pairing it - the same reason
        # DFlash/ is not picked up as this model's drafter. The scanner
        # excludes mmproj-named files from being models in their own right, so
        # the subdirectory adds no junk entry either.
        #
        # If someone tidies that file back next to the weights - or a fresh
        # `club-3090` fetch re-downloads it there - this model quietly drops
        # back to ~15 tok/s. That is the entire failure mode, and there is no
        # log line for it. Check with:
        #   curl -s localhost:8002/props | jq .modalities   # want all false
        #
        # Not done declaratively because there is no way to: every --mmproj
        # variant is on lemonade's reserved list (see below), and its registry
        # treats mmproj as opt-IN via a top-level "mmproj" key that only
        # applies to registry models, not to directory-scanned `extra.` ones.
        # The alternative was re-registering this as `user.muse-glimmer-30b`,
        # which changes the model id everywhere and hits the same "exact
        # repository variant" wall the DFlash note above describes.
        #
        # NOTE the model list is CACHED. After moving the file, lemond keeps
        # serving the stale entry and a load fails with "Hugging Face
        # repository not found". There is no rescan endpoint; round-tripping
        # extra_models_dir forces one:
        #   curl -sX POST -H "Authorization: Bearer $KEY" -d '{"extra_models_dir":""}' \
        #     localhost:13305/internal/set
        #   curl -sX POST -H "Authorization: Bearer $KEY" -d '{"extra_models_dir":"/mnt/games/models"}' \
        #     localhost:13305/internal/set
        #
        # -ngl is NOT set here on purpose. With the projector gone, `auto`
        # takes essentially the whole model and leaves 1465 MiB spare; forcing
        # `-ngl all` would reclaim the last ~670 MiB of layers for maybe 6
        # more tok/s while removing the margin that keeps a load from failing
        # outright (a heavy model that does not fit FAILS rather than evicting
        # the pin - see the gemma entry). Not worth it.
        "extra.muse-glimmer-30b" = {
          ctx_size = 131072;
          llamacpp_backend = "cuda";
          merge_args = true;
          llamacpp_args = builtins.concatStringsSep " " [
            "--parallel 1"
            "--cache-type-k q8_0 --cache-type-v q8_0"
            "--flash-attn on -b 2048 -ub 512"
          ];
        };

        # Qwen3.5-4B - kept as a lighter fallback coordinator, NOT pinned.
        # gemma-4-E4B took the pinned slot once measurement showed it fits
        # (see there). This is ~1 GiB smaller, so it is the thing to fall back
        # to if a heavy model ever needs that GiB more than the coordinator
        # needs vision and audio.
        #
        # Qwen shipped no small dense model after 3.5 (3.6 and 3.8 are
        # 27B-and-up only), so this is the newest 4B that exists.
        #
        # ctx_size 8192 for the same reason as the gemma: routing reads a
        # request and emits a handoff, and light chat needs no more. From the
        # GGUF (8 full-attention layers of 33 at full_attention_interval 4,
        # head_count_kv 4, key/value_length 256 = 2176 B per token per layer at
        # q8_0, plus ~55 MiB of constant SSM state over 25 recurrent layers):
        #   @ 8192 -> 0.18 GiB KV, ~3.17 GiB resident
        #   @32768 -> 0.58 GiB KV, ~3.57 GiB resident
        #
        # Same recurrent-layer caveat as Qwen3.8-27B: 25 of its 33 layers are
        # SSM, so --cache-reuse is unsupported here too. Do not add it.
        #
        # No --model-draft: nextn_predict_layers = 1, i.e. the MTP head is
        # embedded in the GGUF, and lemonade's autodetect turns on draft
        # decoding without a sidecar (confirmed live - it launched with
        # --spec-type draft-mtp and reported draft_n 5 / draft_n_accepted 5).
        "extra.qwen3.5-4b" = {
          ctx_size = 8192;
          llamacpp_backend = "cuda";
          merge_args = true;
          llamacpp_args = builtins.concatStringsSep " " [
            "--parallel 1"
            "--cache-type-k q8_0 --cache-type-v q8_0"
            "--flash-attn on"
          ];
        };

        # gemma-4-E4B - the PINNED coordinator: it decides which model a task
        # goes to, and handles light chat itself. Both jobs need it resident,
        # since a router that must be loaded before it can say what to load
        # costs exactly what routing was meant to save. Quantization-aware
        # trained, so its 4-bit weights are near-lossless rather than merely
        # small, and the only local model here doing audio as well as vision
        # (its mmproj carries a gemma4v vision projector AND a gemma4a audio
        # one, 128 mel bins).
        #
        # Co-residency with Muse Glimmer is MEASURED, not projected - both
        # loaded at once on the 3090, each generating:
        #   desktop baseline                         2872 MiB
        #   + Muse @ full 131072 ctx                18826 MiB
        #   + this @ 8192 ctx WITH the projector    22989 MiB
        #                                    peak   22993 of 24576
        # i.e. ~1.58 GiB spare, at 41.5 tok/s for Muse and 142.9 tok/s here.
        # The projector costs ~0.9 GiB and fits, so vision and audio did not
        # have to be given up - an earlier estimate said 5.3 GiB for this model
        # and the real figure is 4.16 GiB.
        #
        # ctx_size 65536. Routing alone would be happy with 8192, but this
        # model is also the multimodal chat surface, and images and audio are
        # token-expensive in a way text prompts are not - a minute of audio
        # through a 128-mel-bin encoder runs to well over a thousand tokens.
        # More importantly it is Hermes' model.default as of 2026-08-20, and
        # Hermes carries ~20,283 tokens of FIXED overhead before any
        # conversation - a 24,307-char system prompt plus 56,827 chars of tool
        # schemas across 20 tools, measured from the captured request dumps in
        # $HERMES_HOME/sessions. At ctx 32768 that would leave only ~12.5k
        # tokens of working room, which one large file or tool output erases.
        # 65536 leaves ~45k.
        #
        # Cost: 7 full-attention layers of 42, head_count_kv 2,
        # key/value_length 512 = 2176 B per token per layer at q8_0, so KV goes
        # 134 MiB (@8192) -> 483 MiB (@32768) -> ~985 MiB (@65536). Measured
        # headroom with Muse also resident was ~1.39 GiB, so this leaves
        # roughly 0.9 GiB. Do not raise it further without re-measuring.
        #
        # THIS PIN CONSTRAINS THE ROTATING SLOT. A heavy model that does not
        # fit in the ~17.5 GiB left over will fail to load rather than evict
        # the pin. Muse fits at full context because its KV is unusually cheap
        # (13 full-attention layers, head_count_kv 2, 544 B/token/layer).
        # Qwen3.8-27B does NOT: 16 full-attention layers at head_count_kv 4 and
        # key/value_length 256 is 2176 B/token/layer, ~5x Muse per token, so
        # 3.33 GiB of KV at ctx 98304 and ~26.5 GiB needed in total. See the
        # note on its own entry.
        #
        # Its 94 MB MTP drafter is NOT wired up: like Muse Glimmer and unlike
        # the two Qwens, this model has no embedded draft head, so its drafter
        # is a sidecar that only --model-draft could name - and that is
        # reserved. --spec-type is dropped with it, since asking for
        # draft-mtp with no draft head to run it against just fails the load.
        "extra.gemma-4-e4b" = {
          ctx_size = 65536;
          pinned = true;
          llamacpp_backend = "cuda";
          merge_args = true;
          llamacpp_args = builtins.concatStringsSep " " [
            "--parallel 1"
            "--cache-type-k q8_0 --cache-type-v q8_0"
            "--flash-attn on"
          ];
        };
      };

      recipeOptionsFile = (pkgs.formats.json { }).generate "recipe_options.json" recipeOptions;

      recipeOptionsReconcile = pkgs.writeShellApplication {
        name = "lemond-reconcile-recipe-options";
        runtimeInputs = [
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          opts="''${LEMONADE_CACHE_DIR:-''${HOME:-}/.cache/lemonade}/recipe_options.json"
          mkdir -p "$(dirname "$opts")"
          [ -f "$opts" ] || echo '{}' > "$opts"

          # `+`, NOT `*`. `*` merges recursively, which cannot express a
          # REMOVAL: dropping `pinned` from an entry here would leave the
          # previous switch's `"pinned": true` behind on disk forever, because
          # Nix no longer mentions the key for jq to override. (Observed
          # exactly that: unpinning Qwen3.5-4B silently left it pinned
          # alongside its replacement.) `+` is a shallow merge, so every model
          # this module declares gets its whole entry REPLACED and Nix is
          # authoritative for it, while models it says nothing about - the
          # builtin embedding entries and extra.unsloth-iq4nl - are still
          # preserved untouched.
          tmp="$opts.nix-reconcile"
          if jq -s '.[0] + .[1]' "$opts" ${recipeOptionsFile} >"$tmp"; then
            mv "$tmp" "$opts"
          else
            rm -f "$tmp"
            echo "lemond: $opts is unreadable, leaving it untouched" >&2
          fi
        '';
      };
    in
    {
      # Also adds nix-amd-ai's overlay, which rebinds llama-cpp,
      # llama-cpp-vulkan, whisper-cpp-vulkan and the stable-diffusion-cpp
      # variants to derivations built against its own pinned nixpkgs. See the
      # note in nix/overlays.nix about why llama-cpp-cuda sidesteps that.
      imports = [ inputs.nix-amd-ai.nixosModules.default ];

      # Kept for other WebKitGTK apps that *do* pick up session variables
      # normally; lemonade-app itself is fixed above regardless.
      environment.sessionVariables.WEBKIT_DISABLE_DMABUF_RENDERER = "1";

      environment.systemPackages = [ lemonadeAppWebkitFix ];

      # lemond serves on 0.0.0.0 (see lemonade.host below) and warns on every
      # single start that it is doing so without a key:
      #
      #   Serving on non-loopback host '0.0.0.0' without an API key. All
      #   endpoints, including the /internal/* control endpoints and the
      #   /internal/mcp/* process-launch endpoints, are reachable from other
      #   machines unauthenticated.
      #
      # LEMONADE_API_KEY, the full one, which gates EVERY endpoint. Presented
      # as an ordinary bearer token; without it lemond answers
      # {"error": "Invalid or missing API key"}.
      #
      # An admin-only key (LEMONADE_ADMIN_API_KEY, which covers just the
      # /internal/* control plane - process launch via /internal/mcp/*, config
      # rewrites via /internal/set, /internal/shutdown) was the plan while Vane
      # existed, because Vane authenticated with the dummy string "lemonade"
      # kept in an unmanaged docker volume and the full key would have 401'd
      # it. Vane was removed 2026-08-20, so the only caller left is Hermes,
      # which is managed here - and both ends of the secret can therefore land
      # in one commit. Defence in depth rather than strict necessity now that
      # host is loopback, but it costs one line.
      #
      # The decrypted file must contain a literal `LEMONADE_API_KEY=...` line:
      # EnvironmentFile takes KEY=value lines, and ai/hermes-agent.nix feeds
      # the SAME secret to Hermes through its environmentFiles so that
      # providers.lemonade.api_key can interpolate ${LEMONADE_API_KEY}.
      sops.secrets."lemonade-env" = {
        owner = config.hardware.amd-npu.lemonade.user;
        mode = "0400";
      };

      # Concatenates with nix-amd-ai's own lemond-reconcile-config
      # ExecStartPre (systemd merges list-typed Exec* across modules), so
      # both reconcile scripts run before lemond starts.
      systemd.services.lemond.serviceConfig.EnvironmentFile = [
        config.sops.secrets."lemonade-env".path
      ];

      systemd.services.lemond.serviceConfig.ExecStartPre = [
        "${mcpServersReconcile}/bin/lemond-reconcile-mcp"
        "${recipeOptionsReconcile}/bin/lemond-reconcile-recipe-options"
      ];

      # The module has no enableCUDA - it's an AMD-focused flake - so the
      # symlink its defaults.json will point at is ours to create. Same shape
      # as its own lemonadeBackendEtc entries.
      environment.etc."lemonade/backends/llamacpp-cuda".source =
        "${pkgs.llama-cpp-cuda}/bin/llama-server";

      hardware.amd-npu = {
        enable = true;

        # Ryzen AI only. This box is a desktop Raphael + discrete 3090: no
        # XDNA-2 NPU, so the amdxdna module, XRT closure, NPU udev rules and
        # memlock limits would all be dead weight. FastFlowLM is NPU-only and
        # its assertion requires enableNPU, so it goes with it.
        enableNPU = false;
        enableFastFlowLM = false;

        # ROCm targets the Strix iGPUs (the module's gpuTarget enum only
        # offers gfx1150/gfx1151). Leaving it off also keeps llama-cpp-rocm
        # out of the closure - upstream puts that at ~7.6 GB.
        enableROCm = false;

        # Kept on for whispercpp and sdcpp, which get vulkan_bin wired but have
        # no CUDA variant here. For llamacpp it is deliberately NOT the GPU
        # path: lemonade's descriptor lists the vulkan row as supporting only
        # {cpu, amd_gpu}, so on this host it would be a CPU/iGPU fallback.
        enableVulkan = true;

        lemonade = {
          user = "mrpickles";
          # Loopback. This was 0.0.0.0 for exactly one reason - den.aspects.vane
          # ran in a Docker container with its own network namespace, so
          # "localhost" there was the container and nothing bridge-side could
          # reach a 127.0.0.1-bound lemond. Vane was removed 2026-08-20 (it
          # existed only to host the SearxNG that Hermes' web_search pointed at,
          # and that tool turned out never to have been invoked - offered in
          # the tool schema 10 times across captured sessions, called 0 times,
          # with SearxNG serving no real queries in a week).
          #
          # Nothing off-host needs lemond now, so binding loopback removes the
          # whole exposure rather than firewalling around it: no docker0
          # allowedTCPPorts rule, no LEMONADE_ALLOWED_ORIGINS assertion to
          # satisfy, and the "Serving on non-loopback host without an API key"
          # warning stops firing because it only triggers on a non-loopback
          # bind. If a container ever needs lemond again, this goes back to
          # 0.0.0.0 AND allowedOrigins must be set (the module asserts it).
          host = "127.0.0.1";
          port = 13305;
          desktopApp.enable = true;

          # recursiveUpdate'd over the module's computed defaults.json, so
          # these add to its llamacpp section rather than replacing it.
          settings = {
            # Two slots, not one, because one of them is spoken for: the
            # pinned Qwen3.5-4B coordinator in recipeOptions above has to stay
            # resident to do its job. That leaves exactly one rotating slot,
            # shared by the heavy models and the embedding model.
            #
            # NOT -1 (keep everything resident), which this was briefly set to
            # and reverted: with -1 the embedding model permanently squats on
            # ~2 GB that a chat model could use for context, even in sessions
            # that never touch Vane - confirmed then via
            # `nvidia-smi --query-compute-apps`.
            #
            # NOT 3 either, which would let the coordinator, the embedder and a
            # heavy model all stay resident: 3.17 + 0.8 + 17.61 GiB is 21.6 of
            # the ~21.2 GiB usable, so it does not fit while Muse Glimmer runs
            # at its full context. Making it fit would mean a ~1.3 GiB 2B
            # coordinator instead, which is a worse light-chat model - the
            # wrong thing to trade for a rare reload.
            #
            # The eviction worry this was originally written around turned
            # out not to exist: embedding models live in a SEPARATE pool from
            # standard/llm, so they load without consuming an llm slot or
            # evicting anything (verified live - loading the 0.6B embedder
            # alongside two LLMs gave "Total loaded: 3" with no eviction).
            # Vane, the only thing that ever requested embeddings, was removed
            # 2026-08-20, so nothing routinely asks for them at all now.
            # ── Pressure-based eviction: OFF, deliberately ──────────────
            # lemond ships an EvictionEngine with a GlobalVramMonitor, exposed
            # through two keys that appear NOWHERE in defaults.json but are
            # accepted by /internal/set and validated by the binary:
            #   auto_evict                bool   (default false)
            #   auto_evict_threshold_pct  0.0-1.0 (default 0.90)
            # It genuinely works on NVIDIA - the monitor shells out to
            # `nvidia-smi --query-gpu=memory.used,memory.total` - and it
            # respects `pinned`, evicting the rotating model and leaving the
            # coordinator.
            #
            # It is still the wrong mechanism HERE, and the reason is
            # structural rather than a tuning problem: two models resident is
            # already ~94% of the card (23111 of 24576 MiB measured), so there
            # is no band between "normal" and "under pressure". Tested
            # 2026-08-20 at 0.85 - the rotating model was evicted DURING ITS
            # OWN LOAD, twice, and could not stay resident at all:
            #   (on_vram_pressure) VRAM pressure critical (93.97% >= 85.00%).
            #   (evaluate_servers) Eviction Engine unloading model:
            #                      extra.muse-glimmer-30b
            # Raising the threshold above 94% only moves the failure: eviction
            # is reactive and takes ~2s, so a game allocating in a burst has
            # already failed by the time it fires.
            #
            # Stated as false rather than omitted, for the usual reason - the
            # reconcile script shallow-merges over whatever is on disk and
            # cannot express a removal, so a `true` set once by hand would
            # otherwise live in ~/.cache/lemonade/config.json forever. The
            # threshold is left at its default; it does nothing while
            # auto_evict is off, and pinning a number would imply this had a
            # working value.
            #
            # Reclaiming the card for a game is done deterministically instead,
            # from GameMode's custom.start hook - see modules/gaming/gamemode.nix.
            auto_evict = false;

            max_loaded_models = 2;

            # Share the weights club-3090 downloads (its .env pins
            # MODEL_DIR=/mnt/games/models). lemonade scans this with a
            # recursive_directory_iterator and groups GGUFs by parent dir, so
            # club-3090's nested <model>-gguf/<quant>/*.gguf layout is picked
            # up as-is, mmproj sidecars included. Without it the same 17-30 GB
            # quant would be downloaded twice, once per tool.
            extra_models_dir = modelsDir;

            llamacpp = {
              # An absolute path makes find_external_backend_binary() return it
              # directly, which sets needs_install = false in
              # install_from_github() - so lemonade never tries to fetch its own
              # CUDA llama.cpp release. That matters beyond saving a download:
              # upstream's tarballs are ordinary Linux ELFs and would not find a
              # dynamic loader on NixOS.
              cuda_bin = cudaBin;

              # Global fallback args, applied to EVERY llamacpp launch on top
              # of lemonade's computed flags. This existed already as
              # imperative state in ~/.cache/lemonade/config.json (set at some
              # point via the UI or /internal/set) and was silently supplying
              # the --flash-attn on that showed up in launched command lines
              # while nothing in Nix mentioned it. Declared here so it stops
              # being invisible drift; lemond-reconcile-config merges it over
              # the cached copy on every start.
              #
              # Deliberately minimal: it applies to models with no
              # recipeOptions entry too, including whisper/sd recipes' peers
              # and anything newly dropped into extra_models_dir, so it must
              # hold nothing model-specific. Every entry in recipeOptions
              # repeats --flash-attn on rather than relying on this.
              args = "--flash-attn on";
              # Pin the recipe default instead of leaving it "auto". Auto walks
              # the descriptor's preference order - system, metal, cuda, vulkan,
              # rocm, cpu - and "system" comes first, resolving llama-server off
              # PATH, which the llama-cpp aspect also populates. That happens to
              # be the same CUDA binary today, but only by coincidence; naming
              # the backend makes the GPU path explicit and stable.
              backend = "cuda";
            };
          };
        };
      };
    };

  # ── Idle reclamation ──────────────────────────────────────────────────────
  # Day-to-day, the resting state should be the pinned ~4.9 GiB coordinator,
  # not the ~21 GiB full stack: the rotating heavy model is only wanted while
  # something is actually delegating to it. lemond's own idle eviction cannot
  # be reached (evict_idle_timeout / downsize_idle_timeout are rejected by
  # /internal/set as unknown keys), and its pressure-based auto_evict is off
  # for the reasons above, so idleness is tracked from outside instead.
  #
  # A user timer rather than a system one: it reads the sops secret owned by
  # mrpickles and matches the other model-adjacent timers in this config
  # (ai/mnemosyne.nix). It talks to lemond over loopback, so it does not care
  # that lemond itself is a system service.
  den.aspects.lemonade.homeManager =
    { pkgs, ... }:
    let
      idleReaper = pkgs.writeShellApplication {
        name = "lemonade-idle-reaper";
        runtimeInputs = [
          pkgs.curl
          pkgs.gnugrep
          pkgs.coreutils
          pkgs.python3
        ];
        text = builtins.readFile ../../assets/scripts/lemonade-idle-reaper.sh;
      };
    in
    {
      home.packages = [ idleReaper ];

      systemd.user.services.lemonade-idle-reaper = {
        Unit.Description = "Unload idle lemonade models, keeping the pinned coordinator";
        Service = {
          Type = "oneshot";
          # 30 minutes. The reload is cheap when the weights are still in
          # page cache - measured 6.1s end to end, request to reply - so this
          # is not really protecting against reload cost; it is just avoiding
          # churn during a working session. An evening of not using the agent
          # gives ~16 GiB back. Override by editing this, not the script's own
          # default.
          Environment = [ "LEMONADE_IDLE_SECONDS=1800" ];
          ExecStart = "${idleReaper}/bin/lemonade-idle-reaper";
        };
      };

      systemd.user.timers.lemonade-idle-reaper = {
        Unit.Description = "Check every 5 minutes for idle lemonade models";
        Timer = {
          OnBootSec = "10m";
          OnUnitActiveSec = "5m";
          # The check is a single loopback GET; no need to smear it.
          AccuracySec = "1m";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };

}
