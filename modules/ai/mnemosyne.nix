# Mnemosyne (https://github.com/mnemosyne-oss/mnemosyne) as Hermes' external
# memory provider: a local SQLite memory layer with FTS5 + vector recall,
# episodic consolidation and temporal triples, replacing Hermes' built-in
# file-backed memory. Everything stays on this machine - no cloud service and
# no API key, same as the rest of den.aspects' local-AI stack.
#
# Upstream's install path is `pipx install mnemosyne-hermes` into a side venv,
# then `mnemosyne-hermes install --mode wrapper` to link that venv into
# $HERMES_HOME/plugins/. Both steps exist purely because `hermes update`
# rebuilds Hermes' managed venv and wipes anything installed into it. Neither
# is needed here: the plugin is part of the derivation, so nothing can wipe it.
# The remaining upstream steps (`hermes config set memory.provider`,
# `hermes memory setup`) are also unavailable - a home-manager-managed install
# refuses to save config.yaml - so the wizard's answers are declared in
# `settings.memory.mnemosyne` below instead.
#
# ── Why the plugin is a symlink and not extraPlugins ─────────────────────────
# services.hermes-agent.extraPlugins symlinks each entry as
# `plugins/nix-managed-<name>` (moduleCommon.nix), and a memory provider is
# selected by its *directory name* - that prefix would force
# `memory.provider = "nix-managed-mnemosyne"`, which Mnemosyne's own
# `_read_config_key` would then fail to match, since it reads
# `memory.mnemosyne.<key>` from config.yaml by hardcoded name. So the plugin
# goes in through home.file, which controls the final path exactly.
#
# The link target is where this gets subtle. Both
# hermes_memory_provider/__init__.py and its cli.py bootstrap themselves with
#
#     sys.path.insert(0, Path(__file__).resolve().parent.parent)
#
# i.e. they expect their own parent directory to be importable and to contain
# the `mnemosyne` core package - upstream's `ln -s <repo>/hermes_memory_provider
# ~/.hermes/plugins/mnemosyne` layout. Note the `.resolve()`: it follows every
# symlink. Pointing the link straight at a python.withPackages env's
# site-packages therefore does NOT work, because each entry there is itself a
# symlink into a single-package store path - resolve() lands in
# mnemosyne-memory's own site-packages, whose only siblings are mnemosyne and
# hermes_memory_provider. fastembed and sqlite_vec then fail to import, and the
# failure is silent: mnemosyne.core.embeddings guards its fastembed import, so
# the provider still reports available=True while running lexical-only. That
# was confirmed by hand before this shape was settled on.
#
# So pluginRoot below hands resolve() somewhere useful to land: one directory
# holding a real (copied) hermes_memory_provider next to symlinks to the whole
# env. parent.parent then resolves to pluginRoot itself, which has every
# sibling the bootstrap is looking for. Doing it this way rather than patching
# the sys.path line means any other provider file that uses the same idiom -
# cli.py does today - keeps working without a second patch.
#
# ── Why the env carries so little ────────────────────────────────────────────
# That bootstrap is an `insert(0, ...)`, so this env lands at the FRONT of the
# gateway's sys.path and shadows Hermes' own sealed venv for anything both
# provide. Hermes' venv already ships numpy, onnxruntime, tokenizers,
# huggingface-hub, pillow, requests and tqdm - every native dependency
# fastembed has - so those are stripped from the closure here rather than
# duplicated. This is not only about size:
#
#   * shadowing Hermes' pinned versions with different ones is exactly the
#     breakage its extraPythonPackages collision check exists to prevent, and
#     that check does not cover this path;
#   * nixpkgs' onnxruntime for python312 is not in any binary cache (python312
#     is not this nixpkgs' default python), so keeping it would mean compiling
#     onnx + onnxruntime from source - roughly an hour - on every nixpkgs bump,
#     to produce a copy that sys.path ordering guarantees is never imported.
#
# Verified against the running gateway's interpreter: fastembed loads Hermes'
# onnxruntime 1.27.0, embeds at 384 dims (BAAI/bge-small-en-v1.5), and the
# sqlite-vec vec0 tables (vec_working / vec_facts / vec_episodes) are created.
#
# Model weights are fetched from HuggingFace on first use into
# $HERMES_HOME/cache/fastembed (~130 MB) - Mnemosyne's own default, not
# something set here. The SQLite database lands in $HERMES_HOME/mnemosyne/data.
{ den, inputs, ... }:
{
  den.aspects.mnemosyne.homeManager =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      # Must match the interpreter hermes-agent itself runs on - the provider
      # is imported into the gateway process, so a different minor version
      # cannot load its native extension modules. nix/hermes-agent.nix pins
      # python312.
      python = pkgs.python312;
      py = pkgs.python312Packages;

      # Distributions Hermes' sealed venv already provides. See the header:
      # these are dropped from the closure so this env cannot shadow them.
      fromHermesVenv = [
        "huggingface-hub"
        "numpy"
        "onnxruntime"
        "pillow"
        "pyyaml"
        "requests"
        "tokenizers"
        "tqdm"
      ];

      # dontCheckRuntimeDeps: the wheel still declares the dropped names in its
      # metadata, and the runtime-deps hook would fail the build over them.
      # pythonImportsCheck: importing fastembed without onnxruntime present
      # fails for the same reason - the import is exercised at runtime against
      # Hermes' venv instead.
      dropHermesVenvDeps =
        drv:
        drv.overridePythonAttrs (old: {
          dependencies = builtins.filter (p: !(builtins.elem (p.pname or "") fromHermesVenv)) (
            old.dependencies or [ ]
          );
          dontCheckRuntimeDeps = true;
          pythonImportsCheck = [ ];
        });

      # python312Packages.sqlite-vec does not build: its checkPhase pulls in
      # openai, whose own checkPhase pulls inline-snapshot, whose test suite
      # fails on python312 (it is not this nixpkgs' default python, so nobody
      # is testing that combination). doCheck=false keeps nativeCheckInputs out
      # of openai's build inputs entirely, so inline-snapshot is never built.
      # Drop this override once nixpkgs' inline-snapshot passes on 3.12.
      openai = py.openai.overridePythonAttrs (_: {
        doCheck = false;
      });

      sqlite-vec = dropHermesVenvDeps (py.sqlite-vec.override { inherit openai; });
      fastembed = dropHermesVenvDeps py.fastembed;

      mnemosyne = py.buildPythonPackage {
        pname = "mnemosyne-memory";
        version = "3.15.1";
        pyproject = true;
        src = inputs.mnemosyne;

        # setuptools' packages.find has no `where`, and upstream's exclude list
        # covers neither of these, so both would install as generic top-level
        # `examples` / `integrations` modules in site-packages - which this env
        # then puts at the front of the gateway's sys.path. Deleting them is
        # narrower than rewriting the exclude list. (mnemosyne/integrations, the
        # real subpackage, is untouched.)
        postPatch = "rm -rf examples integrations";

        build-system = [
          py.setuptools
          py.wheel
        ];

        # PyYAML, the one hard dependency, comes from Hermes' venv. fastembed
        # and sqlite-vec are the `[embeddings]` extra; the `[llm]` extra is
        # deliberately skipped - it wants ctransformers, which is not in
        # nixpkgs, and local consolidation can go through llama.cpp instead.
        dependencies = [
          fastembed
          sqlite-vec
        ];

        dontCheckRuntimeDeps = true;
        doCheck = false;
        pythonImportsCheck = [ "mnemosyne" ];

        meta = {
          description = "Local-first SQLite memory layer for AI agents";
          homepage = "https://github.com/mnemosyne-oss/mnemosyne";
          license = lib.licenses.mit;
        };
      };

      mnemosyneEnv = python.withPackages (_: [ mnemosyne ]);
      sitePackages = "${mnemosyneEnv}/${python.sitePackages}";

      # See the header: hermes_memory_provider must be a real directory here,
      # so that its own `Path(__file__).resolve().parent.parent` bootstrap
      # lands on this derivation and finds the rest of the env beside it.
      # Everything else stays a symlink - imports follow those happily, it is
      # only resolve() on the provider's own path that matters.
      pluginRoot = pkgs.runCommand "mnemosyne-hermes-plugin" { } ''
        mkdir -p $out
        for entry in ${sitePackages}/*; do
          name=$(basename "$entry")
          [ "$name" = "hermes_memory_provider" ] && continue
          ln -s "$entry" "$out/$name"
        done
        cp -r ${mnemosyne}/${python.sitePackages}/hermes_memory_provider $out/
        chmod -R u+w $out/hermes_memory_provider

        # plugin.yaml is not shipped in the wheel (setuptools installs .py
        # only), and Hermes' general PluginManager wants one at the plugin
        # root. The memory-provider loader itself only looks for __init__.py,
        # so this is belt and braces - but a missing manifest is the kind of
        # thing that turns into a confusing "plugin not found" later.
        cp ${inputs.mnemosyne}/hermes_memory_provider/plugin.yaml \
          $out/hermes_memory_provider/plugin.yaml
      '';

      hermesCfg = config.services.hermes-agent;

      # home.file keys are relative to $HOME, hermesHome is absolute.
      hermesHomeRel = lib.removePrefix "${config.home.homeDirectory}/" hermesCfg.hermesHome;

      # Mnemosyne's own CLI (backup, export, doctor, reindex, verify) run on
      # Hermes' interpreter rather than a bare python312, so it sees the same
      # numpy and onnxruntime the provider does. On its own python it would
      # silently lose vector recall - mnemosyne.core.embeddings guards its
      # numpy import and degrades to lexical-only - and quietly disagree with
      # what the agent is doing to the same database.
      #
      # PYTHONPATH prepends, but nothing in this env is also in Hermes' venv
      # (see fromHermesVenv above), so there is nothing to shadow.
      mnemosyne-cli = pkgs.writeShellScriptBin "mnemosyne" ''
        export PYTHONPATH=${sitePackages}''${PYTHONPATH:+:$PYTHONPATH}
        exec ${hermesCfg.package.hermesVenv}/bin/python3 -m mnemosyne.cli "$@"
      '';

      # ── Obsidian bridge ──────────────────────────────────────────────────
      # The SecondBrain vault, not ~/Documents/"Obsidian Vault" - that one is
      # the dormant sibling, and the OBSIDIAN_VAULT_PATH that used to point at
      # it was wrong (removed along with obsidian-second-brain on 2026-08-20;
      # see modules/ai/hermes-agent.nix). SecondBrain is what both surviving
      # cron jobs read and write.
      vault = "/home/mrpickles/Documents/SecondBrain";
      vaultFolder = "Mnemosyne";

      # Written here rather than using upstream's own Obsidian plugin
      # (integrations/obsidian-mnemosyne, "Mnemosyne Sync"), which cannot work:
      # its embedded Python is mis-indented and raises IndentationError before
      # it opens the database, it calls .get() on a sqlite3.Row (no such
      # method), and it looks for <bank>.db when the file is mnemosyne.db. It
      # also ships only main.ts - no built main.js - against a README telling
      # you to download one. All three confirmed by running it, 2026-08-20.
      #
      # Plain python3 (the default 3.14, already cached) is enough: the script
      # shells out to the mnemosyne CLI above for the export and then only does
      # json + pathlib work. It deliberately does NOT read mnemosyne.db
      # directly - going through `mnemosyne export` keeps it off the schema and,
      # more importantly, away from the sqlite-vec vec0 virtual tables, which
      # is what breaks readers that iterate sqlite_master.
      mnemosyne-obsidian-export = pkgs.writeShellApplication {
        name = "mnemosyne-obsidian-export";
        runtimeInputs = [
          pkgs.python3
          mnemosyne-cli
        ];
        text = ''
          exec python3 ${../../assets/scripts/mnemosyne-obsidian-export.py} \
            --vault ${lib.escapeShellArg vault} \
            --folder ${lib.escapeShellArg vaultFolder} \
            "$@"
        '';
      };

      # ── Scheduled consolidation ──────────────────────────────────────────
      # The llama.cpp server from modules/ai/llama-cpp.nix, which is also what
      # Hermes' "vllm" provider points at (the name is historical - see
      # modules/ai/hermes-agent.nix).
      llmBaseUrl = "http://localhost:18020/v1";
      llmHealthUrl = "http://localhost:18020/health";

      mnemosyne-consolidate = pkgs.writeShellApplication {
        name = "mnemosyne-consolidate";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.gnused
          mnemosyne-cli
        ];
        text = builtins.readFile ../../assets/scripts/mnemosyne-consolidate.sh;
      };
    in
    {
      home.file."${hermesHomeRel}/plugins/mnemosyne".source = "${pluginRoot}/hermes_memory_provider";

      home.packages = [
        mnemosyne-cli
        mnemosyne-consolidate
        mnemosyne-obsidian-export
      ];

      systemd.user.services.mnemosyne-consolidate = {
        Unit.Description = "Consolidate Mnemosyne working memory into episodic summaries";
        Service = {
          Type = "oneshot";
          # Decrypts to a literal `VLLM_API_KEY=...` line; the script
          # re-exports it as MNEMOSYNE_LLM_API_KEY rather than introducing a
          # second copy of the same key under a new name.
          EnvironmentFile = osConfig.sops.secrets."hermes-agent-vllm-env".path;
          Environment = [
            "MNEMOSYNE_LLM_BASE_URL=${llmBaseUrl}"
            "MNEMOSYNE_HEALTH_URL=${llmHealthUrl}"
            # llama-server's -a/--alias, same id Hermes sends.
            "MNEMOSYNE_LLM_MODEL=qwen3.8-27b"
            # Default is 60s. A measured pass took ~23s wall for 8 memories,
            # but this shares a single-slot server, so a request can sit behind
            # a live turn before it even starts.
            "MNEMOSYNE_LLM_TIMEOUT=300"
          ];
          ExecStart = "${mnemosyne-consolidate}/bin/mnemosyne-consolidate";
        };
      };

      # Hourly, but the script consolidates at most once a day - see its header.
      # The point is to catch the first hour llama-server happens to be up,
      # since it is started by hand and holds ~20GB of VRAM.
      systemd.user.timers.mnemosyne-consolidate = {
        Unit.Description = "Hourly attempt at the daily Mnemosyne consolidation";
        Timer = {
          OnCalendar = "hourly";
          Persistent = true;
          RandomizedDelaySec = "10m";
        };
        Install.WantedBy = [ "timers.target" ];
      };

      # Daily rather than the plugin's 30-minute default. Memories accrue over
      # hours, not minutes, and this writes into a vault that a sync client is
      # watching - there is nothing to gain from churning it.
      #
      # This is the only thing left that writes to a vault on its own, and it
      # is deliberately a plain script rather than a Hermes cron job: no model
      # in the loop means it cannot paraphrase or invent, unlike the LLM-driven
      # jobs whose prompts have to beg for byte-for-byte transcription. It only
      # ever touches ${vaultFolder}/, never deletes, and skips any note whose
      # body no longer matches the content_sha it was written with - so a note
      # edited by hand in Obsidian is left alone rather than overwritten.
      systemd.user.services.mnemosyne-obsidian-export = {
        Unit.Description = "Export Mnemosyne memories to the ${vaultFolder} folder in Obsidian";
        Service = {
          Type = "oneshot";
          ExecStart = "${mnemosyne-obsidian-export}/bin/mnemosyne-obsidian-export";
        };
      };

      systemd.user.timers.mnemosyne-obsidian-export = {
        Unit.Description = "Daily Mnemosyne -> Obsidian export";
        Timer = {
          OnCalendar = "daily";
          # The vault is only interesting to read when the machine is up, and a
          # missed day should still land rather than waiting for the next one.
          Persistent = true;
          RandomizedDelaySec = "15m";
        };
        Install.WantedBy = [ "timers.target" ];
      };

      services.hermes-agent.settings = {
        memory = {
          provider = "mnemosyne";

          # Upstream (and every tutorial) tells you to disable built-in memory
          # once a provider is active, to stop the same facts being injected
          # twice. Deliberately NOT done here, and it is worth knowing why
          # before "tidying" these two keys back in:
          #
          # ~/.hermes/memories/MEMORY.md is the source the weekly cron job
          # "Mirror agent memory to SecondBrain" (Sundays 20:00) transcribes
          # into Knowledge/Agent Memory.md in the SecondBrain vault. That job
          # reads the MEMORY block injected into its own system prompt, and its
          # rules say to rewrite the note whenever the entries differ - so
          # switching built-in memory off empties the block, and the next run
          # would faithfully mirror nothing over the audit note.
          #
          # The duplication argument also does not carry much weight here:
          # MEMORY.md + USER.md come to ~2.1 KB, against the ~22 KB the tools
          # allowlist below already saves. Cheap enough to run both layers side
          # by side - built-in memory as the small human-auditable set that
          # reaches the vault, Mnemosyne as the large automatic one.
          #
          # Set explicitly rather than left unset. Activation deep-merges these
          # settings into config.yaml and keeps every key it does not declare,
          # so a `false` once written there is never cleaned up by dropping the
          # option - it has to be overwritten. Stating true also stops the
          # desktop app's toggles from turning them off behind the config's
          # back, since these keys are reapplied on every activation.
          #
          # (For reference: they default to TRUE via
          # hermes_cli/config_defaults.py, not to false as agent_init.py's own
          # `mem_config.get(..., False)` fallback suggests.)
          memory_enabled = true;
          user_profile_enabled = true;

          # The answers `hermes memory setup` would have collected, from the
          # provider's own get_config_schema(). Only the non-default ones are
          # set here.
          mnemosyne = {
            # The one that matters: 'session' (the default) scopes every
            # remembered fact to the session that produced it, which defeats
            # the point of a persistent memory layer. 'global' persists across
            # sessions, so the Discord gateway, the CLI and cron jobs all share
            # one memory.
            default_scope = "global";

            # Off, against upstream's default. auto_sleep fires a consolidation
            # inline once working memory passes sleep_threshold (50), and with
            # an LLM backend configured that is a ~23s call against a
            # single-slot llama-server - i.e. a stall dropped into whatever
            # turn happens to cross the threshold. The systemd timer below runs
            # the same pass on a schedule instead, when the machine is idle.
            #
            # Nothing is lost by waiting: sleep only ever considers working
            # memories older than WORKING_MEMORY_TTL_HOURS // 2 = 84h, and they
            # are not evicted until 168h, so every entry has a ~3.5 day window
            # in which a scheduled pass can pick it up.
            auto_sleep = false;

            # Per-profile isolation via Mnemosyne banks. Off, matching
            # upstream's default: this config runs a single Hermes profile, and
            # turning it on later would strand the existing database under
            # data/ rather than data/banks/<profile>/.
            profile_isolation = false;

            # Tool-schema allowlist. Unset, Mnemosyne registers 40 tools worth
            # 26.8 KB of schema - measured with `hermes prompt-size`, where it
            # was 38% of a 69.6 KB tool-schema total, on top of the 46.8 KB
            # this config already carried. Prefill dominates latency here (a
            # cold Discord turn measured 17.8s processing 19,582 tokens against
            # 1.9s generating), so that is the expensive part of running a
            # memory provider, and it is easy to miss: provider tools bypass
            # the toolset registry, so `hermes prompt-size` files them under an
            # `(unknown)` toolset rather than under mnemosyne.
            #
            # These five cover the automatic capture/recall loop, which is the
            # whole point of the provider. Measured 5 tools / 4,588 bytes, so
            # roughly 22 KB off every prompt.
            #
            # Dropped, and what you give up: the sync_* tools (remote sync
            # server - not run here), persona_* (the L3 persona tier),
            # graph_* and triple_* (explicit edges and temporal triples),
            # *_canonical plus model_card/model_refresh (canonical self-fact
            # slots), shared_* (the cross-bank shared surface),
            # scratchpad_* , batch/import/export and the diagnose/validate
            # helpers. All real features, but none of them fire on their own -
            # they need the agent to be deliberately driven at them. Add a name
            # back here when that is actually wanted.
            #
            # This key is read ONLY from config.yaml, via the provider's
            # _read_config_key - passing `tools` as an initialize() kwarg is
            # silently ignored, so this is the only place it can be set. A
            # misspelled name here raises at startup rather than quietly
            # dropping the tool.
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
    };
}
