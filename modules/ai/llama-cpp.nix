{ den, ... }:
{
  den.aspects.llama-cpp.nixos =
    { pkgs, ... }:
    {
      # llama-cpp-cuda comes from nix/overlays.nix, which also explains why it
      # is built from its own nixpkgs instance. The same derivation backs
      # lemonade's llamacpp.cuda_bin (see ai/lemonade.nix), so there is exactly
      # one CUDA llama.cpp in the closure rather than two.
      #
      # No binary cache carries a cudaSupport llama-cpp: cache.nixos.org has
      # only the CPU/BLAS build and the top-level llama-cpp-vulkan, and
      # cuda-maintainers.cachix.org has neither. So this compiles locally on
      # every llama.cpp or CUDA-stack bump - the post-build-hook in
      # nix/settings.nix pushes the result to the personal Cachix, which is
      # what makes a rollback or a second machine cheap.
      environment.systemPackages = [
        # llama.cpp installs its libggml-*.so backend plugins into $out/bin
        # next to the executables, so they land in /run/current-system/sw/bin
        # too. That's how nixpkgs ships it; the binaries find their backends
        # relative to their own resolved path, so splitting them out would
        # break the CUDA backend load.
        pkgs.llama-cpp-cuda
      ];
    };

  # Qwen3.8-27B served over llama.cpp's OpenAI-compatible API, as the backend
  # for den.aspects.hermes-agent (which points providers.vllm at
  # http://localhost:18020/v1 - the name is historical, see that module).
  #
  # Replaced a patched-vLLM Docker stack on 2026-08-19. That stack's own
  # README advertised 111-124 tok/s, but only via CTX=fast, which never fit on
  # this card once the desktop session's ~1.9 GiB is accounted for; the config
  # that actually ran here (CTX=huge / KVarN) measured 25-57 tok/s of
  # generation under real traffic. This path measures 57-62 tok/s with 81-89%
  # MTP draft acceptance, so the migration cost no throughput.
  #
  # A user service, not a system one: it reads a sops secret owned by
  # mrpickles, and it pairs with hermes-agent.service which is already
  # user-scoped. Both rely on `users.users.mrpickles.linger`.
  den.aspects.llama-cpp.homeManager =
    { osConfig, pkgs, ... }:
    let
      modelDir = "/mnt/games/models/qwen3.8-27b-gguf/unsloth-ud-q4km";

      # The API key lives in the same sops secret hermes-agent consumes, as a
      # literal `VLLM_API_KEY=...` line (that shape is required by Hermes'
      # environmentFiles). llama-server wants the bare value, so this sources
      # the file and re-exports it under llama.cpp's own env var rather than
      # duplicating the secret under a second name. LLAMA_API_KEY (not
      # --api-key) keeps the key out of the process's argv, where any local
      # user could read it from `ps`.
      # NOT passed: --cache-reuse. It looks like the right fix for Hermes'
      # prompt layout - the memory block sits ~3.5k chars into a ~24k system
      # prompt, so every memory update invalidates the ~85% downstream of it,
      # including all ~47 KB of tool schemas - but llama-server rejects it on
      # this model at load time:
      #   srv load_model: cache_reuse is not supported by this context,
      #                   it will be disabled
      # Consistent with the architecture: 48 of Qwen3.8's 64 layers are
      # DeltaNet recurrent (full_attention_interval 4), and a recurrent state
      # cannot be position-shifted the way attention KV can, which is what
      # cache reuse does. Plain longest-common-prefix caching still works and
      # is what makes follow-up turns cheap; only mid-conversation memory
      # writes fall off it. Do not re-add the flag expecting it to help.
      serve = pkgs.writeShellScript "llama-server-qwen38" ''
        set -a
        . ${osConfig.sops.secrets."hermes-agent-vllm-env".path}
        set +a
        export LLAMA_API_KEY="$VLLM_API_KEY"

        exec ${pkgs.llama-cpp-cuda}/bin/llama-server \
          --model       ${modelDir}/Qwen3.8-27B-UD-Q4_K_M.gguf \
          --model-draft ${modelDir}/MTP/mtp-Qwen3.8-27B-Q4_0.gguf \
          --spec-type draft-mtp --spec-draft-n-max 2 \
          -ngl 99 -ngld 99 -fa on \
          -ctk q8_0 -ctv q8_0 \
          -c 98304 -ub 512 -b 2048 -np 1 \
          --jinja -a qwen3.8-27b \
          --reasoning-budget 192 \
          --host 127.0.0.1 --port 18020
      '';
    in
    {
      systemd.user.services.llama-server-qwen38 = {
        Unit = {
          Description = "llama.cpp serving Qwen3.8-27B (MTP) for Hermes";
          # Ordering only, not a dependency: hermes-agent tolerates the
          # endpoint being down (it retries), and this unit is started by
          # hand, so a Requires= here would drag one down with the other.
          After = [ "graphical-session.target" ];
        };

        Service = {
          ExecStart = "${serve}";
          # Weights are ~16.6 GiB off an NVMe and CUDA graph capture follows,
          # so a cold start is tens of seconds; the default 90s TimeoutStop is
          # fine but startup must not be killed early.
          TimeoutStartSec = "600";
          Restart = "no";
          # Frees the card promptly when stopped for a gaming session.
          KillSignal = "SIGINT";
        };

        # Deliberately NO Install.wantedBy - this must not autostart.
        #
        # The model holds ~20.9 GiB of a 24 GiB card for its entire run, and
        # this box also gets used for gaming on the same GPU (Steam/gamescope,
        # Polaris GameStream). An autostarting unit would either lose the race
        # with a game or silently deny it VRAM. Same rationale as the
        # `restart: "no"` override the retired vLLM compose carried.
        #
        # Start/stop with the llama-start / llama-stop fish functions
        # (modules/shell/fish.nix).
      };
    };
}
