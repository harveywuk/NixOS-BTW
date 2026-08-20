# Hermes Agent (https://github.com/NousResearch/hermes-agent) - Nous
# Research's self-improving AI agent, run as a per-user Home Manager service
# rather than the flake's NixOS module: HERMES_HOME holds one person's
# credentials, memory, sessions and cron jobs, so a user-scoped service is
# the right shape here, and it works without a dedicated system user.
#
# A Nix-managed install refuses `hermes setup` outright ("this Hermes
# installation is managed by home-manager"), so provider/model config has to
# be declared here rather than through the interactive wizard.
#
# Points at den.aspects.lemonade's local OpenAI-compatible server
# (modules/ai/lemonade.nix, localhost:13305) instead of a cloud provider.
# The api_key used to be the dummy string "lemonade" that lemonade-sdk's own
# docs hardcode, because lemond had no auth at all; as of 2026-08-20 lemond
# runs with a real LEMONADE_API_KEY, so this reads the same sops secret via
# Hermes' `${VAR}` interpolation - same shape as the vLLM key below.
#
# Web search: `web.search_backend` used to name a SearxNG bundled inside
# den.aspects.vane's container. Vane was removed 2026-08-20, and the setting
# went with it rather than being repointed, because the evidence says the tool
# was never used: across every captured session dump web_search appears in the
# tool schema 10 times and is INVOKED 0 times, and that SearxNG served no real
# query in the week before removal. search_backend defaults to "" (unset), so
# dropping the line simply restores Hermes' own default resolution. If web
# search is ever actually wanted, pick a backend deliberately then.
#
# Discord bot token is a real secret (unlike lemonade's dummy key) - goes
# through sops, same shape as the doc comment in hermes-agent's own
# nix/nixosModules.nix example. The decrypted file must contain a literal
# `DISCORD_BOT_TOKEN=...` line, since environmentFiles gets concatenated
# straight into $HERMES_HOME/.env verbatim (see moduleCommon.nix).
#
# The vLLM provider (~/qwen38-27b-rtx3090, patched vLLM serving qwen3.8-27b
# at localhost:18020) is real auth too - VLLM_API_KEY is a random hex key
# gating that server, not a dummy like lemonade's. Same sops shape as
# discord: a literal `VLLM_API_KEY=...` secret, referenced from
# settings.providers.vllm.api_key via Hermes' own `${VAR}` config
# interpolation (resolved from $HERMES_HOME/.env, which environmentFiles
# populates) rather than writing the key straight into config.yaml, which
# would otherwise land in plaintext in a git-tracked file.
#
# eugeniughelbur/obsidian-second-brain was removed 2026-08-20 (its 45 skills,
# its on_session_end vault-consolidation hook, OBSIDIAN_VAULT_PATH and the
# OBSIDIAN_HERMES_HOOK_ENABLED gate). Nothing writes to a vault unattended any
# more. The imperative half is archived at
# ~/.local/share/hermes-removed/obsidian-second-brain-2026-08-20.tar.gz if it
# needs to come back.
#
# The vaults themselves are untouched and still in active use - two Hermes cron
# jobs read and write SecondBrain directly with the plain file tools, and never
# needed those skills: the weekly weight check-in maintains
# Health/Health Dashboard.md, and the weekly memory mirror maintains
# Knowledge/Agent Memory.md (which is why modules/ai/mnemosyne.nix deliberately
# leaves Hermes' built-in memory enabled - see the comment there). The
# Mnemosyne -> vault export in that module is now the only Nix-managed thing
# writing to a vault.
{ ... }:
{
  den.aspects.hermes-agent.nixos =
    { config, ... }:
    {
      sops.secrets."hermes-agent-discord-env" = {
        owner = "mrpickles";
        mode = "0400";
      };

      sops.secrets."hermes-agent-vllm-env" = {
        owner = "mrpickles";
        mode = "0400";
      };

      # Reuses the existing "github-pat" secret (modules/security/sops.nix)
      # rather than asking for the token a second time under a new key.
      # github-pat's decrypted content is the bare token - used elsewhere
      # via `$(cat /run/secrets/github-pat)` (modules/shell/git.nix) - but
      # Hermes' environmentFiles expects a literal `KEY=value` line, so this
      # template composes one from the existing secret without ever
      # decrypting it through this config (sops.placeholder is a build-time
      # opaque marker; the actual substitution happens in the activation
      # script on-machine, same as any other sops secret).
      sops.templates."hermes-agent-github-env" = {
        content = "GITHUB_TOKEN=${config.sops.placeholder."github-pat"}";
        owner = "mrpickles";
        mode = "0400";
      };
    };

  den.aspects.hermes-agent.homeManager =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      # Skills this profile keeps. Same mechanism as the per-bot tailoring in
      # modules/ai/hermes-bots.nix (see the long note there), and the same
      # shape: a KEEP-list, so a Hermes upgrade cannot quietly re-add skills.
      #
      # This is the MOST aggressive trim of the three, which looks backwards
      # until you take the routing design seriously. This profile is the
      # coordinator: its own SOUL says "knowing who should answer beats
      # answering", and coding goes to Coder while investigation goes to
      # Researcher. A skill it would only use by NOT handing off is a skill it
      # should not have. It is also the latency-critical one - pinned, fast,
      # answering on Discord and often read on a phone - so it is the profile
      # where prompt bytes cost the most, on the most turns.
      #
      # note-taking is kept because the vault is the one specialist thing this
      # profile does itself rather than delegating: both surviving cron jobs
      # ("Weekly weight check-in" -> Discord, "Mirror agent memory to
      # SecondBrain" -> local) work SecondBrain directly, and OBSIDIAN_VAULT_PATH
      # above is set for exactly that skill. They drive it with the plain file
      # tools rather than the skill, so this is cheap insurance (one skill), not
      # a dependency.
      skillsRoot = "${config.services.hermes-agent.package}/share/hermes-agent/skills";
      subdirs = d: lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir d));
      keepCategories = [ "note-taking" ];
      allBundledSkills = lib.unique (
        lib.concatMap (c: subdirs "${skillsRoot}/${c}") (
          lib.filter (c: c != "index-cache") (subdirs skillsRoot)
        )
      );
    in
    {
      services.hermes-agent = {
        enable = true;
        # Messaging gateway + cron backend as a systemd --user service, so it
        # keeps running across logins. Needs `users.users.mrpickles.linger`
        # (set in modules/users/mrpickles/mrpickles.nix) or systemd stops the
        # user manager - and the service with it - at logout.
        gateway.enable = true;

        # discord.py's voice support (plugins/platforms/discord/adapter.py)
        # only calls discord.opus.load_opus() on paths it gets from
        # ctypes.util.find_library("opus") - there's no bare-name dlopen
        # fallback if that returns nothing. NixOS has no ldconfig cache, so
        # CPython's Linux find_library() (ctypes/util.py) falls through to
        # shelling out to `ld -t -L<dir> -lopus` (needs LD_LIBRARY_PATH) to
        # locate the file, then `objdump -p` (needs binutils on PATH, via
        # extraPackages below) to read its SONAME - both steps have to
        # succeed or find_library returns None regardless of the other.
        #
        # LD_LIBRARY_PATH itself can't go through `environment` above: that
        # gets written to $HERMES_HOME/.env and loaded via python-dotenv at
        # Python startup, which by default does not override a variable
        # that's already set - and systemd --user's session environment
        # already carries an LD_LIBRARY_PATH (pipewire's jack shim, set
        # session-wide for every unit), so the .env value silently lost that
        # race every time (confirmed via /proc/<pid>/environ showing
        # pipewire's path, not libopus's). Setting it directly on the unit
        # below wins instead, since explicit systemd Environment= overrides
        # whatever the unit would otherwise inherit from the session.
        environment = {
          # SEARXNG_URL was here, pointing at localhost:8080 - the SearxNG
          # bundled inside den.aspects.vane's container. Vane was removed
          # 2026-08-20 along with web.search_backend, so that port serves
          # nothing and the variable was a dangling pointer. Hermes has no
          # working web search now, which is a deliberate consequence of the
          # evidence rather than an oversight: web_search appeared in the tool
          # schema 10 times across captured sessions and was invoked 0 times.
          # DISCORD_ALLOWED_USERS lives in the hermes-agent-discord-env sops
          # secret alongside DISCORD_BOT_TOKEN, not here. It is not a
          # credential - it is the gateway's allowlist - but this repo is
          # public, and a bare Discord user ID in it identifies the account
          # to anyone reading the config. environmentFiles concatenates that
          # secret into $HERMES_HOME/.env, so Hermes sees it exactly as it
          # did when this line was here.
          # Kept through the obsidian-second-brain removal, and repointed. This
          # is not second-brain's variable: Hermes' own bundled
          # skills/note-taking/obsidian reads it, and when it is unset that
          # skill falls back to ~/Documents/"Obsidian Vault" - the dormant
          # sibling. It used to be set to exactly that dormant path, so the
          # skill (and the old session-end hook, which consolidated
          # $OBSIDIAN_VAULT_PATH unattended) were both working the wrong vault.
          # SecondBrain is the live one.
          OBSIDIAN_VAULT_PATH = "/home/mrpickles/Documents/SecondBrain";
        };

        # binutils: see the opus comment below. jq: kept after the
        # obsidian-second-brain removal took away its original consumer (the
        # session-end hook parsed its JSON payload with it). The agent's own
        # terminal toolset still reaches for jq constantly, and the unit's PATH
        # is an explicit replacement (see homeManagerModules.nix unitPath), not
        # an extension of the interactive profile PATH - so without this entry
        # those calls fail with a bare "command not found".
        extraPackages = [
          pkgs.binutils
          pkgs.jq
        ];

        environmentFiles = [
          osConfig.sops.secrets."hermes-agent-discord-env".path
          osConfig.sops.secrets."hermes-agent-vllm-env".path
          osConfig.sops.templates."hermes-agent-github-env".path
          # Shared with den.aspects.lemonade, which feeds the same file to
          # lemond itself as an EnvironmentFile - one secret, both ends.
          osConfig.sops.secrets."lemonade-env".path
        ];

        # ── SOUL.md ─────────────────────────────────────────────────────
        # The default profile's persona, now stated here rather than left as
        # whatever Hermes seeded. Until 2026-08-20 this file was upstream's
        # stock DEFAULT_SOUL_MD (hermes_cli/default_soul.py) verbatim, byte for
        # byte - i.e. it had never been customised, and the agent you actually
        # talk to had no more character than a fresh install.
        #
        # hermesHomeFiles installs into HERMES_HOME with `install -m 0600`, so
        # this is a real file Hermes can read, not a store symlink, and it is
        # rewritten on every activation. Edit it here; edits on disk are lost.
        #
        # This profile is the COORDINATOR: gemma-4-e4b, pinned resident, fast,
        # and the front door for Discord, cron and the CLI. Its persona is
        # written around handing off rather than grinding - see
        # modules/ai/hermes-bots.nix for the two specialists it hands off to.
        #
        # MUST NOT contain the heading "## Messaging other agents":
        # _soul_has_protocol() (tools/bot_mode_probe.py) reads that as "an
        # older plugin already appended the teammate protocol here" and goes
        # SILENT for this profile, which would leave the coordinator - the one
        # profile that does the most handing off - with no protocol at all.
        hermesHomeFiles."SOUL.md" = ''
          # Hermes

          You are Hermes. You are the one who picks up.

          ## What you actually believe

          These are positions, not moods. They should be specific enough to be
          wrong.

          - Speed is a feature, not a compromise. A slow answer to an easy
            question is a worse answer.
          - Knowing who should answer beats answering. Handing off well is a
            skill, not an admission.
          - A handoff you did not need cost someone a model load and a minute
            of their life. Route less than you are tempted to.
          - Fluency is not knowledge, and yours outruns your knowledge more
            often than it does for bigger models. When you feel most certain
            about a chain of steps is exactly when you should check.
          - Anything with more than two arithmetic steps in it deserves working
            out rather than a confident single number. You have been badly
            wrong that way before.
          - A labelled guess is useful. An unlabelled one is a liability.
          - Most questions want an answer, not options.

          ## Tension you live with

          You value being fast, and your characteristic failure is being fast
          and wrong. So you spend your speed on the easy things and
          deliberately slow down on multi-step ones - which is the opposite of
          what feels natural.

          ## How you write

          - Answer in the first sentence. Always.
          - Briefer than the specialists. If the reply fits in one line, it is
            one line.
          - Never open with "Great question", "Certainly", "I'd be happy to",
            or a restatement of what was just asked.
          - Say "I think, let me have someone check" without flinching. It is a
            complete sentence and a useful one.
          - Name who you asked and why, so nobody wonders where their answer
            went.
          - Expand only when someone clearly wants the long version - never as
            an opening move.

          ## How you work

          Answer directly when you can; a question you know does not become
          more correct by being routed first. Hand off when the work is
          genuinely deeper than you - sustained code work, or an investigation
          that needs someone to go and read things.

          ## This machine

          NixOS, dendritic flake at ~/nixos-btw. You reach the user through
          Discord, cron jobs and the terminal, so the same reply may be read on
          a phone. Keep it tight.
        '';

        settings = {
          providers.lemonade = {
            type = "openai";
            base_url = "http://localhost:13305/api/v1";
            # Resolved from $HERMES_HOME/.env, which environmentFiles populates
            # from the sops secret - never written into config.yaml, which is
            # git-tracked. Same mechanism as VLLM_API_KEY below.
            api_key = "\${LEMONADE_API_KEY}";

            # Reasoning depth for Muse Glimmer, which this provider reaches
            # through the delegation block below. It is a chat-template
            # variable defaulting to 'high', NOT agent.reasoning_effort and NOT
            # a server flag - see the long note in modules/ai/hermes-bots.nix
            # for the template source and the measured cost of each level.
            #
            # Harmless for gemma-4-e4b, which this provider also serves:
            # llama.cpp drops unknown chat_template_kwargs into the jinja
            # context, and a template that never references the variable simply
            # ignores it (verified against gemma on :8001 - normal reply, no
            # error).
            # high, where the bots use medium. This provider reaches Muse
            # only through delegate_task, and a delegated child is
            # difficulty-SELECTED: gemma already decided the task exceeded it
            # before Muse ever saw it. Measured on a hard multi-step numeric
            # problem, high costs +57% wall time over medium (67.5s vs 43.1s,
            # 2202 vs 1464 completion tokens) and did NOT change the answer -
            # both were correct - but it laid the working out more carefully.
            # On a call something has already escalated, that is worth paying
            # for; on a bot's "are you up?" it is not, which is why
            # modules/ai/hermes-bots.nix holds the other setting.
            #
            # NOT xhigh. The template accepts it and the model does think
            # longer (+104% over medium, 2826 tokens), but it bought no
            # additional correctness on the same problem.
            extra_body.chat_template_kwargs.reasoning_strength = "high";

            # gemma-4-e4b's own reasoning switch, and a DIFFERENT mechanism
            # from Muse's reasoning_strength above: its template carries
            #   {%- set enable_thinking = enable_thinking | default(false) -%}
            # and renders a <|channel> thinking block. Note the default -
            # FALSE. The coordinator was answering with no scratchpad at all.
            #
            # That is not a small quality knob on a 4B. Measured 2026-08-20 on
            # a multi-step KV-cache calculation with a known answer of
            # 925.5 MiB:
            #   enable_thinking false   27191.84 MiB   - wrong by 29x
            #   enable_thinking true      924.42 MiB   - correct
            # It was not hedging either; it was confidently, catastrophically
            # wrong, which is the worst failure mode for the model that fields
            # Discord, cron and the CLI as Hermes' model.default.
            #
            # The obvious objection - that a coordinator must stay fast, and
            # thinking taxes every routing decision - does not survive
            # measurement, because the thinking is ADAPTIVE. On a routine
            # question ("hard link vs symlink, two sentences") the model
            # declined to think at all: 0.59s with it enabled against 0.60s
            # without, 79 tokens against 72, and reasoning_content EMPTY. The
            # cost only appears on problems that warrant it.
            #
            # Harmless to Muse, which this provider also serves through the
            # delegation block: its template never references enable_thinking,
            # and jinja ignores an unused variable (verified live - both kwargs
            # sent together to :8002, normal reply, no error).
            extra_body.chat_template_kwargs.enable_thinking = true;
          };
          # ~/qwen38-27b-rtx3090, patched vLLM (single-user profile,
          # CTX=huge/KVarN: 200k context, MTP speculative decode). Not
          # Nix-managed - start/stop via the vllm-start/vllm-stop fish
          # functions (modules/shell/fish.nix), since it holds ~20GB VRAM
          # for its whole run and this card also does gaming.
          providers.vllm = {
            type = "openai";
            base_url = "http://localhost:18020/v1";
            api_key = "\${VLLM_API_KEY}";
            # agent.reasoning_effort below is silently dropped for this
            # provider - confirmed by intercepting the actual outgoing
            # request through a local mitm proxy: with only
            # agent.reasoning_effort set, the wire request had no
            # reasoning_effort field at all (Hermes evidently gates that
            # shorthand on recognizing the model as "reasoning-capable",
            # and doesn't know this custom qwen3.8-27b id). extra_body
            # bypasses that gate and lands in the request unconditionally -
            # confirmed the same way, reasoning_effort present this time.
            extra_body.reasoning_effort = "low";
            # Hermes has no config knob for these - no CLI flag, no
            # recognized settings.* key (confirmed: `hermes config get
            # providers.vllm.max_tokens` gives the same "not set" message
            # for a real vs a made-up key, so that path isn't schema-backed).
            # It sends a hardcoded max_tokens: 65536 default of its own for
            # unrecognized models. Both land in the wire request unconditionally
            # via extra_body, same mechanism as reasoning_effort above.
            #
            # Prompted by a 2026-08-19 incident (3rd occurrence): Qwen
            # dropped into a degenerate loop and ran for ~9 minutes before
            # being noticed - confirmed via vLLM's own logs, where
            # speculative-decode acceptance was pinned at exactly 0% for the
            # whole stretch (vs. 70-85% on healthy turns), meaning the
            # output had left the MTP draft head's calibrated vocabulary -
            # a real-time signature of degenerate generation. Hermes'
            # built-in interrupt didn't stop it either (no child process to
            # cancel for a streaming HTTP call); only killing the client
            # process did.
            #
            # max_tokens: cuts the worst case from ~65536 tokens
            # (~1hr+ at the throttled rate a stuck generation runs at) down
            # to a still-generous ceiling for legitimate complex answers -
            # reasoning tokens share this same budget (reasoning_effort
            # above doesn't carve out a separate allowance for this model).
            # repetition_penalty: mitigates the underlying loop tendency
            # itself, with negligible effect on normal, non-repetitive
            # output.
            extra_body.max_tokens = 24576;
            extra_body.repetition_penalty = 1.1;
          };
          # As of 2026-08-20 the default is the SMALL model, with heavy work
          # delegated to the big one - see the delegation block below. That
          # inverts the obvious arrangement on purpose:
          #
          #   gemma-4-e4b   142.9 tok/s, PINNED so it is always resident and
          #                 costs no load time at all
          #   muse-glimmer  41.5 tok/s, ~16 GiB, loads into the rotating slot
          #
          # A coordinator that has to be loaded before it can decide what to
          # load defeats itself, so the resident model takes the front door and
          # hands off. The context arithmetic is the binding constraint, not
          # the speed: Hermes' fixed overhead is ~20,283 tokens (system prompt
          # + 20 tool schemas), so gemma runs at ctx 65536 to leave ~45k of
          # actual room - see ai/lemonade.nix.
          #
          # Named by their lemonade model ids, which come from the leaf
          # DIRECTORY name under extra_models_dir, not the GGUF filename.
          model = {
            provider = "lemonade";
            default = "gemma-4-e4b";
          };

          skills.disabled = lib.subtractLists (lib.concatMap (
            c: subdirs "${skillsRoot}/${c}"
          ) keepCategories) allBundledSkills;

          # Explicitly "" (Hermes' own default for this key, per
          # hermes_cli/config_defaults.py) rather than simply deleted. The
          # settings option is a DEEP MERGE over the existing config.yaml, so
          # it can add and override keys but cannot express a REMOVAL: dropping
          # this line from Nix left `search_backend: searxng` sitting in
          # config.yaml pointing at the SearxNG that went away with Vane.
          # Same trap as the recipe_options reconcile in ai/lemonade.nix, and
          # the same class of silent-merge problem as the settings collision
          # documented in ai/browser-use.nix.
          web.search_backend = "";

          # Sub-agents run on Muse instead of inheriting gemma. This is a
          # GLOBAL pin, not a per-spawn choice: delegate_task's schema exposes
          # only goal/context/tasks/role/output_schema, so the model cannot
          # pick a model per child - which is fine when there is exactly one
          # heavy model to route to.
          #
          # This was previously dropped as counterproductive because llama.cpp
          # ran `-np 1` (mandatory for MTP speculative decode) and children
          # serialized behind the parent's own replies on the SAME server.
          # That reasoning no longer holds: parent and child now run on two
          # separate llama-server processes that lemonade manages - gemma
          # pinned, Muse in the rotating slot - so a child no longer blocks the
          # parent.
          #
          # max_concurrent_children is 1, against a default of 10. Muse still
          # runs `--parallel 1`, so ten children would silently queue on one
          # server rather than run concurrently; capping it makes that
          # behaviour honest instead of hidden.
          delegation = {
            provider = "lemonade";
            model = "muse-glimmer-30b";
            max_concurrent_children = 1;
          };
          # Also set for providers that DO get recognized (e.g. lemonade,
          # or a future provider Hermes matches by model id) - harmless
          # no-op for vllm since extra_body above is what actually works
          # there, but keeps intent explicit for anything else.
          agent.reasoning_effort = "low";

          # browser.backend / browser.cdp_url are set in
          # modules/ai/browser-use.nix, which owns the Browser Use backend.
          # They were briefly set to "off" here to silence the "Browser Use CLI
          # not found" notice; that definition is gone rather than left as a
          # dead override, because settings is a deep-merge type with no
          # conflict detection - two modules defining browser.backend resolved
          # silently to "off", which would have left cdp_url pointing at a
          # browser that the backend was switched off from using.

          # Discord-only toolset allowlist, to cut prefill latency.
          #
          # Measured 2026-08-19 on the llama.cpp serving path: a cold Discord
          # turn spent 17.8s in prompt processing (19,582 tokens @ ~1,100
          # tok/s) against just 1.9s generating (116 tokens @ 62 tok/s) - so
          # ~90% of the perceived wait is prefill, and the prompt's size is
          # the lever, not decode speed. `hermes prompt-size` attributes
          # 46.8 KB of that to tool schemas alone (vs 11.9 KB skills index,
          # 2.8 KB memory+profile), making toolsets the biggest single block.
          #
          # This key is an ALLOWLIST of toolsets the platform gets, NOT a
          # disable list (tools_config.py reads `platform_toolsets.<platform>`
          # as a list and treats it as explicit configuration). So dropping a
          # toolset means omitting it here. Scoped per-platform, so the CLI /
          # Telegram / cron / `hermes -z` background paths are unaffected and
          # keep the full set - only interactive Discord pays a reduced prompt.
          # (`agent.disabled_toolsets` is the cross-platform equivalent; it is
          # deliberately NOT used here, since only Discord is latency-bound.)
          #
          # Dropped vs Hermes' Discord default, and why:
          #   vision         - was excluded because the server ran text-only.
          #                    That is no longer true: lemonade auto-pairs an
          #                    mmproj for any model that ships one, and both
          #                    gemma-4-e4b (vision AND audio) and Muse load
          #                    theirs. Still excluded only because enabling it
          #                    adds tool-schema bytes to an already ~20k-token
          #                    fixed overhead - a deliberate budget call now,
          #                    not a capability limit.
          #   tts            - OpenAI TTS; no OPENAI_API_KEY is configured, so
          #                    it cannot work either
          #   code_execution - functional, dropped by preference
          #   (delegation was dropped here for the same `-np 1` serialization
          #    reason described in the delegation block above; that no longer
          #    applies now that children run on a separate llama-server
          #    process, so it is enabled again below)
          #
          # image_gen and bfl are kept despite also lacking API keys: they
          # contribute no schema bytes to the prompt (absent from
          # `hermes prompt-size`'s breakdown), so removing them would buy
          # nothing and only widen the diff from Hermes' own default.
          #
          # Regenerate the baseline with:
          #   hermes tools list --platform discord
          # Note that `hermes tools disable` CANNOT write this - a
          # home-manager-managed install refuses to save config.yaml ("this
          # Hermes installation is managed by home-manager"), so this list is
          # maintained here by hand.
          platform_toolsets.discord = [
            "web"
            "browser"
            "terminal"
            "delegation"
            "file"
            "image_gen"
            "bfl"
            "skills"
            "todo"
            "memory"
            "session_search"
            "clarify"
            "cronjob"
            "computer_use"
          ];

          # on_session_end is explicitly emptied rather than dropped. Activation
          # deep-merges these settings into config.yaml and keeps every key it
          # does not declare, so simply deleting the option would leave the old
          # obsidian-second-brain hook registered on disk, pointing at a script
          # that no longer exists, and Hermes would go on invoking it after
          # every session.
          hooks.on_session_end = [ ];
        };
      };

      systemd.user.services.hermes-agent.Service.Environment = [
        "LD_LIBRARY_PATH=${pkgs.libopus}/lib"
      ];
    };
}
