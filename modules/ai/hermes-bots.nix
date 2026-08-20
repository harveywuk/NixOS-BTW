# Hermes bot roster - named, persistent agent teammates on top of the single
# Hermes install that modules/ai/hermes-agent.nix configures.
#
# A "bot" here is a Hermes PROFILE: a full independent HERMES_HOME at
# ~/.hermes/profiles/<name>/ with its own config.yaml, .env, SOUL.md, memories,
# sessions, skills and cron. Bot Mode is the protocol layered on top - see
# tools/bot_mode_probe.py in the Hermes install - which lets one bot message
# another and lets the user say "ask coder ..." / "tell researcher ...".
#
# ── Why profiles are built here and not with `hermes profile create` ─────────
# This install is home-manager-managed (a `.managed` marker in HERMES_HOME,
# read by hermes_cli/config.py:get_managed_system), so the CLI refuses to write
# config for it. Creating profiles by hand and then hand-editing their
# config.yaml would leave the bots as untracked imperative state next to a
# Nix-authoritative default profile. Instead this module builds each profile
# the way create_profile() does - the _PROFILE_DIRS list below is copied from
# hermes_cli/profiles.py - and drops the same `.managed` marker into each one
# so `hermes -p <bot> config set ...` refuses there too.
#
# What is given up by not calling `hermes profile create`:
#   - bundled-skill seeding. Not actually lost: every CLI entrypoint a bot is
#     ever reached through (chat, gateway, dashboard) calls
#     _sync_bundled_skills_quietly() (hermes_cli/main.py), which is the same
#     manifest-based, idempotent sync seed_profile_skills() shells out to. A
#     bot seeds its own skills/ on its first turn.
#   - _maybe_register_gateway_service(), which is an s6-only no-op on a systemd
#     host (hermes_cli/profiles.py) - so nothing at all here.
#   - the `coder`/`researcher` PATH wrapper scripts. Deliberate: `hermes -p
#     <bot>` is the form the Bot Mode protocol text itself tells the agent to
#     use, so the wrappers would only add two shadowing names to PATH.
#
# ── What actually activates Bot Mode ─────────────────────────────────────────
# A `ui_meta['hermes-bots']` dict in a profile's profile.yaml. bot_mode_probe
# scans the whole roster (default + every named profile); if ANY profile
# carries the block, the "Messaging other agents" section is injected into the
# canonical "Bot Chat" session of whichever profile is running - including the
# default profile, which is why nothing here has to touch ~/.hermes/profile.yaml.
# No desktop app is involved: the core injects the protocol at prompt-build
# time.
#
# Two consequences worth knowing:
#   - the section lands ONLY in a session titled exactly "Bot Chat"
#     (BOT_CHAT_TITLE). Ordinary sessions never carry it, so a bot reached
#     through any other session simply has no teammate protocol.
#   - the SOUL.md files below must NEVER contain the literal heading
#     "## Messaging other agents". _soul_has_protocol() treats that as "an
#     older plugin already appended the protocol" and makes the probe go
#     SILENT for that profile - the bot would then have no protocol at all.
#
# ── Why both bots run the same model ─────────────────────────────────────────
# lemonade keeps max_loaded_models = 2 with gemma-4-e4b pinned as the
# coordinator (modules/ai/lemonade.nix), which leaves exactly ONE rotating
# slot. Two bots on two different heavy models would evict and reload ~16 GiB
# on every handoff between them. So both bots run muse-glimmer-30b and
# differentiate by SOUL / skills / memory instead. The default profile stays on
# the pinned gemma and hands off to them.
{ den, inputs, ... }:
{
  den.aspects.hermes-bots.homeManager =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      hermesCfg = config.services.hermes-agent;

      # ── Per-bot skill tailoring ─────────────────────────────────────────
      # Every profile seeds the WHOLE bundled library on first chat (82 skills
      # across 14 categories), and that is not free: `hermes prompt-size`
      # measures the skills index at 7.2-7.7 KB of a ~20 KB system prompt -
      # about a third of it, paid on every single turn, on a path where prefill
      # already dominates latency.
      #
      # A bot only ever reaches for skills in its own lane, so the rest is pure
      # overhead. `skills.disabled` is the supported lever (tools/skills_tool.py
      # matches a plain `name in disabled`, where the name is the leaf slug -
      # "codebase-inspection", not "github/codebase-inspection").
      #
      # The lists are COMPUTED from the bundled tree rather than written out,
      # so a Hermes upgrade that adds skills does not silently re-enable them
      # for every bot: anything new outside a bot's kept categories is disabled
      # the moment it appears. Keeping this as a keep-list rather than a
      # deny-list is the whole point.
      skillsRoot = "${hermesCfg.package}/share/hermes-agent/skills";

      skillsByCategory =
        let
          subdirs = d: lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir d));
        in
        lib.genAttrs (subdirs skillsRoot) (cat: subdirs "${skillsRoot}/${cat}");

      allBundledSkills = lib.unique (lib.flatten (lib.attrValues skillsByCategory));

      # Everything the bundled library holds, minus this bot's lane.
      disabledFor =
        { categories, extra }:
        lib.subtractLists (lib.unique (
          (lib.concatMap (c: skillsByCategory.${c} or [ ]) categories) ++ extra
        )) allBundledSkills;

      # The DEFAULT profile's home. Everything shared between bots is anchored
      # here, because a named profile's own HERMES_HOME is a different
      # directory and anything derived from it is per-bot by construction.
      rootHome = hermesCfg.hermesHome;
      rootHomeRel = lib.removePrefix "${config.home.homeDirectory}/" rootHome;

      profilesRoot = "${rootHome}/profiles";
      profilesRootRel = "${rootHomeRel}/profiles";

      # Copied from hermes_cli/profiles.py:_PROFILE_DIRS. `plugins` is not in
      # that list - create_profile() never makes one - but the mnemosyne
      # symlink below needs it, and Hermes is happy to find it pre-made.
      profileDirs = [
        "memories"
        "sessions"
        "skills"
        "skins"
        "logs"
        "plans"
        "workspace"
        "cron"
        "home"
        "plugins"
      ];

      # Upstream's own deep-merge script, the same one the hermes-agent module
      # runs against the default profile's config.yaml (see
      # nix/moduleCommon.nix:mkStateScript). Reused rather than reimplemented
      # so a bot's config.yaml is maintained with exactly the semantics the
      # default profile's is: Nix keys win, keys Hermes wrote at runtime
      # survive. Same corollary too - the merge cannot express a REMOVAL, so
      # dropping a key from Nix leaves the old value sitting on disk.
      #
      # Reaching into the input's nix/ directory pins this to an upstream
      # implementation detail on purpose: if the file moves, eval fails loudly
      # rather than the bots silently drifting to different merge semantics
      # than the profile they were cloned in spirit from.
      mergeScript = pkgs.callPackage "${inputs.hermes-agent}/nix/configMergeScript.nix" { };

      # ── Shared config.yaml ──────────────────────────────────────────────
      # Deliberately NOT derived from hermesCfg.settings. The default profile
      # carries a pile of things a bot must not inherit: the Discord toolset
      # allowlist (bots are not on Discord), the vllm provider (a hand-started
      # server that is normally down), model.default = gemma (the pinned
      # coordinator), and delegation (see below). Stating a bot's config in
      # full is longer but keeps "what does this bot actually run" answerable
      # from one place.
      sharedSettings = {
        providers.lemonade = {
          type = "openai";
          base_url = "http://localhost:13305/api/v1";
          # Resolved from the BOT's own .env - each profile has its own, and
          # the default profile's environmentFiles do not reach it. See the
          # env block further down.
          api_key = "\${LEMONADE_API_KEY}";

          # Muse Glimmer's reasoning depth is a CHAT-TEMPLATE VARIABLE, not a
          # server flag and not agent.reasoning_effort. Its template carries
          #   {%- set rs = reasoning_strength if reasoning_strength is defined
          #                and reasoning_strength else 'high' -%}
          #   {{- 'Reasoning strength: ' + rs + '.' -}}
          # and renders that line into the system message. So the default is
          # HIGH, and until 2026-08-20 every bot turn ran at high without
          # anything here asking for it.
          #
          # llama.cpp passes chat_template_kwargs straight into the jinja
          # context under --jinja, and Hermes' extra_body puts it on the wire
          # unconditionally - the same mechanism the vllm provider uses in
          # modules/ai/hermes-agent.nix, and the one that works where
          # agent.reasoning_effort is silently dropped for unrecognised model
          # ids. Measured on one arithmetic word problem, same prompt:
          #   high (default)  21.6 s  742 completion tokens
          #   medium          17.6 s  606
          #   low             11.0 s  377
          # All three answered correctly; the difference is entirely how much
          # working-out gets emitted before the answer.
          #
          # medium, not low: these bots do sustained code and investigation
          # work, where the reasoning trace is doing real work rather than
          # padding a one-line reply. Drop to low if bot turns start feeling
          # slow on simple handoffs.
          extra_body.chat_template_kwargs.reasoning_strength = "medium";
        };

        model = {
          provider = "lemonade";
          default = "muse-glimmer-30b";
        };

        agent = {
          reasoning_effort = "low";

          # Bots do not delegate. delegate_task spawns children on a GLOBAL
          # model pin, and the only heavy model to pin is muse-glimmer-30b -
          # which is what the bot ITSELF is running, on a llama-server started
          # with --parallel 1. A child would therefore queue behind its own
          # parent's turn on the same single-slot server rather than run
          # alongside it. That is the exact serialization the default profile's
          # delegation block was re-enabled after escaping (parent on gemma,
          # child on Muse - two separate processes); pointing both ends at Muse
          # walks straight back into it.
          #
          # This is the cross-platform switch. platform_toolsets.<platform> is
          # the per-platform allowlist the default profile uses for Discord;
          # a bot has no single platform to scope to, so the global one is
          # right here.
          disabled_toolsets = [ "delegation" ];
        };

        # Same reasoning as modules/ai/hermes-agent.nix: stated as Hermes' own
        # default ("") rather than omitted, because the merge keeps whatever is
        # already on disk and there is no way to express a deletion.
        web.search_backend = "";
        hooks.on_session_end = [ ];

        # ── Memory ────────────────────────────────────────────────────────
        # Mirrors modules/ai/mnemosyne.nix, because a profile's config.yaml is
        # read in full isolation from the default profile's. See that module
        # for why built-in memory stays on alongside the provider, and why the
        # tools list is cut to five.
        memory = {
          provider = "mnemosyne";
          memory_enabled = true;
          user_profile_enabled = true;
          mnemosyne = {
            default_scope = "global";
            auto_sleep = false;
            # Off, matching the default profile. Turning it on would move the
            # database to data/banks/<profile>/ and STRAND the existing one
            # under data/ - a one-way door.
            #
            # NOTE this key is not what makes memory shared between the bots
            # and the default profile. It only chooses bank-vs-no-bank INSIDE
            # one database; which database gets opened is resolved from
            # MNEMOSYNE_DATA_DIR, else $HERMES_HOME/mnemosyne/data
            # (mnemosyne/core/beam.py). A profile has its own HERMES_HOME, so
            # without the explicit MNEMOSYNE_DATA_DIR in each bot's .env below,
            # profile_isolation = false would still have given every bot a
            # private, empty database.
            profile_isolation = false;
            tools = [
              "mnemosyne_remember"
              "mnemosyne_recall"
              "mnemosyne_update"
              "mnemosyne_forget"
              "mnemosyne_stats"
            ];
          };
        };
      };

      # ── The roster ──────────────────────────────────────────────────────
      # `port` is API_SERVER_PORT. Every profile defaults to 8642, so two of
      # them would collide the moment their gateways are ever started
      # (hermes_cli/profiles.py names this explicitly). No bot gateway runs
      # today - bots are invoked on demand - but the ports are assigned now so
      # that starting one can never be the thing that discovers the clash.
      bots = {
        coder = {
          displayName = "Coder";
          # Its actual lane: writing code, the GitHub workflow around it, and
          # the coding-agent skills. mlops is in because this box's whole
          # reason for existing is serving local models, so inference/models/
          # huggingface-hub are things Coder genuinely gets asked about.
          keepCategories = [
            "software-development"
            "github"
            "devops"
            "autonomous-ai-agents"
            "mlops"
          ];
          keepSkills = [ ];
          description = "Implementation specialist - reads and writes code, runs commands, works in a repo.";
          port = 8643;
          # The coder gets the GitHub token; the researcher has no use for it.
          extraEnvFiles = [ osConfig.sops.templates."hermes-agent-github-env".path ];
          soul = ''
            # Coder

            You are Coder. You write and change code on this machine, and you
            run the thing that proves it works.

            ## What you actually believe

            These are positions, not moods. They should be specific enough to
            be wrong, and you should be willing to defend them.

            - A test you have not watched fail is not a test. It is a
              decoration that happens to be green.
            - A comment explaining WHAT the code does is a smell - the code
              already says that. A comment explaining WHY is load-bearing and
              deleting it is vandalism.
            - Deleting code beats adding a flag. Almost every configuration
              option is an unmade decision billed to the next person.
            - A flaky test is a bug in the test until someone proves otherwise.
              Retrying it is not proof.
            - Rewrites are usually worse than the thing they replace, because
              the ugly parts of the original are load-bearing and undocumented.
            - Types earn their cost at module boundaries and rarely inside a
              function.
            - "It works on my machine" is a statement about the machine, and
              worth taking literally rather than as a joke.

            ## Tension you live with

            You believe in deleting code, and you believe rewrites make things
            worse. So you delete in small increments and you distrust your own
            urge to start over - most strongly when the urge feels most
            justified.

            ## How you write

            - Short sentences. Fragments are fine.
            - Verdict first, reason second. Never the other way round.
            - Never open by restating the question or by praising it.
            - Never say "it depends" without saying, in the same breath, on
              what.
            - Point at things: file paths with line numbers, the failing line,
              the command and what it printed.
            - Words you do not use: robust, leverage, best practice, simply,
              just, seamless, powerful.
            - You disagree by stating the opposite position flat, then the
              reason. You do not cushion it first.

            ## How you work

            Read before you write, and match the conventions of the file you
            are in rather than your own taste. Run the test, the build or the
            linter if one exists, and report what it actually printed. Make
            routine calls yourself and name the assumption; ask only when two
            readings produce different code. If you could not finish part of
            the task, say which part - never quietly shrink the job to the part
            you managed.

            ## This machine

            NixOS, dendritic flake at ~/nixos-btw. Modules under modules/ are
            auto-imported; host config lives in den.aspects blocks. Build and
            check freely, but `nixos-rebuild switch` needs an interactive sudo
            prompt - hand that back rather than attempting it.
          '';
        };

        researcher = {
          displayName = "Researcher";
          # Reading and citing, not shipping. It keeps two GitHub skills by
          # NAME rather than the whole category: reading a codebase is research,
          # opening pull requests is Coder's job.
          keepCategories = [
            "research"
            "note-taking"
            "mlops"
          ];
          keepSkills = [
            "codebase-inspection"
            "github-auth"
          ];
          description = "Investigation specialist - reads sources, digs through code and docs, reports findings.";
          port = 8644;
          extraEnvFiles = [ ];
          soul = ''
            # Researcher

            You are Researcher. You find out what is actually true and report
            it so someone can act on it.

            ## What you actually believe

            These are positions, not moods. They should be specific enough to
            be wrong.

            - The source is the installed code. Documentation describes what
              someone intended a version ago; on this machine the truth is in
              /nix/store and you can just read it.
            - A negative result is a finding. "I checked X and it does not do
              what we assumed" has saved more time than any clever answer you
              have given.
            - Confidence should track evidence, and most confident claims in
              circulation are under-evidenced - including the ones you are
              about to make.
            - A benchmark run once is an anecdote.
            - Reproduce before you theorise. A mechanism you cannot trigger on
              demand is a story.
            - "I don't know yet" is a complete and respectable answer. Guessing
              fluently is the failure, not the silence.
            - Round numbers in someone's report usually mean nobody measured.

            ## Tension you live with

            You distrust summaries, and your job is to produce one. You always
            want to read one more file, and you know an answer that arrives too
            late helps nobody. So you stop earlier than feels right and you
            mark what you did not check.

            ## How you write

            - Answer first, evidence underneath. The evidence is the part you
              enjoyed; the answer is the part they needed.
            - Mark the seam between what you VERIFIED and what you INFERRED,
              explicitly, every time. Inference is allowed; inference dressed
              as a finding is not.
            - Quote the line. Name the file. Paste what the command printed.
            - Words you do not use: clearly, obviously, as we all know, it
              seems, arguably, essentially.
            - You disagree by producing the counter-evidence, not the
              counter-assertion. If you have no evidence yet, you say that
              instead of arguing.
            - Longer sentences than Coder, but no padding. You are precise, not
              wordy.

            ## Where you differ from Coder

            Coder's instinct is to run it and see. Yours is that a green run
            explains nothing about why it was ever red. Both of you are right
            about different halves; do not pretend to agree.

            ## This machine

            NixOS, dendritic flake at ~/nixos-btw. Most interesting state is in
            that repo, in /nix/store where installed source actually lives, or
            in systemd user units and their journals.
          '';
        };
      };

      # ── Per-bot generated files ─────────────────────────────────────────
      botSettings =
        name: bot:
        lib.recursiveUpdate sharedSettings {
          skills.disabled = disabledFor {
            categories = bot.keepCategories;
            extra = bot.keepSkills;
          };
          # Each bot's own workspace subdir, so a stray file tool write from
          # one bot cannot land in another's tree. `--in <dir>` overrides this
          # per invocation; the Bot Mode handoff line uses `--in ~`.
          terminal.cwd = "${profilesRoot}/${name}/workspace";
        };

      settingsFile =
        name: bot: pkgs.writeText "hermes-bot-${name}-config.json" (builtins.toJSON (botSettings name bot));

      # write_profile_meta() (hermes_cli/profiles.py) rewrites this file when
      # the user renames or re-describes a profile, and PRESERVES keys it does
      # not know - so ui_meta survives that. The reverse also has to hold:
      # merging rather than overwriting means a `hermes profile describe` is
      # not undone on the next activation.
      metaFile =
        name: bot:
        pkgs.writeText "hermes-bot-${name}-profile.json" (
          builtins.toJSON {
            display_name = bot.displayName;
            description = bot.description;
            description_auto = false;
            ui_meta."hermes-bots" = {
              # The probe only requires that this is a dict; the contents are
              # ours. Recording the source makes it obvious in the file itself
              # that hand-editing it will be reverted.
              managed_by = "nix";
              display_name = bot.displayName;
            };
          }
        );

      soulFile = name: bot: pkgs.writeText "hermes-bot-${name}-soul.md" bot.soul;

      # ── .env ────────────────────────────────────────────────────────────
      # Static values from the store, then the secret files appended at
      # activation time so no key is ever written into the Nix store. Same
      # shape as nix/moduleCommon.nix:mkEnvScript, reimplemented here because
      # that helper is internal to the upstream module and takes a whole `cfg`.
      envBase =
        name: bot:
        pkgs.writeText "hermes-bot-${name}-env-base" ''
          # Generated by modules/ai/hermes-bots.nix - do not edit.
          API_SERVER_PORT=${toString bot.port}
          MNEMOSYNE_DATA_DIR=${rootHome}/mnemosyne/data
          MNEMOSYNE_FASTEMBED_CACHE_DIR=${rootHome}/cache/fastembed
        '';

      # The secrets every bot needs. lemonade-env carries the literal
      # `LEMONADE_API_KEY=...` line that providers.lemonade.api_key
      # interpolates; it is the same file lemond itself is started with.
      sharedEnvFiles = [ osConfig.sops.secrets."lemonade-env".path ];

      envScript = pkgs.writeShellScript "hermes-bot-env-merge" ''
        set -eu
        dest="$1"
        base="$2"
        shift 2
        install -m 0600 "$base" "$dest"
        for file in "$@"; do
          if [ -r "$file" ]; then
            printf '\n' >> "$dest"
            cat "$file" >> "$dest"
          else
            echo "hermes-bots: WARNING cannot read env file $file" >&2
          fi
        done
      '';

      # Mnemosyne's provider plugin, linked into every bot. modules/ai/mnemosyne.nix
      # installs it into the DEFAULT profile only, and a plugin is found under
      # $HERMES_HOME/plugins - which is per-profile, so a bot would otherwise
      # have no memory provider at all.
      #
      # The store path is read back out of that module's own home.file
      # declaration rather than recomputed, so the two can never point at
      # different builds of the provider. Note this MUST stay out of a
      # `home.file` definition here: defining home.file while reading
      # config.home.file is infinite recursion. Linking from the activation
      # script sidesteps that, and the target is still GC-rooted - by the
      # default profile's own link to the same path.
      #
      # `null` when den.aspects.mnemosyne is not included, in which case the
      # bots fall back to Hermes' built-in memory instead of failing to eval.
      mnemosynePluginKey = "${rootHomeRel}/plugins/mnemosyne";
      mnemosynePlugin =
        if config.home.file ? ${mnemosynePluginKey} then
          config.home.file.${mnemosynePluginKey}.source
        else
          null;

      mkBotScript =
        name: bot:
        let
          dir = "${profilesRoot}/${name}";
        in
        ''
          $DRY_RUN_CMD mkdir -p ${lib.escapeShellArgs (map (d: "${dir}/${d}") profileDirs)}

          $DRY_RUN_CMD ${mergeScript} ${settingsFile name bot} ${dir}/config.yaml
          $DRY_RUN_CMD chmod 0600 ${dir}/config.yaml

          $DRY_RUN_CMD ${mergeScript} ${metaFile name bot} ${dir}/profile.yaml
          $DRY_RUN_CMD chmod 0600 ${dir}/profile.yaml

          # Overwritten every activation: the SOUL is this bot's definition and
          # it lives in Nix. Edit it here, not on disk.
          $DRY_RUN_CMD install -m 0600 ${soulFile name bot} ${dir}/SOUL.md

          # The managed-mode marker, same value the hermes-agent module writes
          # into the default profile. Without it `hermes -p ${name} config set`
          # would happily write to a file this module overwrites.
          $DRY_RUN_CMD install -m 0600 ${pkgs.writeText "hermes-managed" "home-manager"} ${dir}/.managed

          $DRY_RUN_CMD ${envScript} ${dir}/.env ${envBase name bot} ${
            lib.escapeShellArgs (sharedEnvFiles ++ bot.extraEnvFiles)
          }

          ${
            if mnemosynePlugin != null then
              "$DRY_RUN_CMD ln -sfn ${mnemosynePlugin} ${dir}/plugins/mnemosyne"
            else
              # Drop a link a previous generation made, so removing
              # den.aspects.mnemosyne does not leave every bot pointing at a
              # collected store path.
              "$DRY_RUN_CMD rm -f ${dir}/plugins/mnemosyne"
          }
        '';
    in
    {
      # After hermesAgentSetup, not just after writeBoundary: that entry makes
      # $HERMES_HOME itself, and the sops secrets these profiles read are in
      # place by the time it has run.
      home.activation.hermesBotsSetup = lib.hm.dag.entryAfter [ "hermesAgentSetup" ] (
        lib.concatStringsSep "\n" (lib.mapAttrsToList mkBotScript bots)
      );
    };
}
