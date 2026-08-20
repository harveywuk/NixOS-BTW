# Browser Use as Hermes' browser backend, replacing the built-in browser tools.
#
# What this actually is: Hermes pipes Python to the `browser-use` CLI on stdin
# and reads stdout back (tools/browser_use_cli.py). browser-use is a scripting
# runtime with pre-imported CDP helpers - `goto_url`, `click_at_xy`, `js`,
# `capture_screenshot` - and the code is written by the model Hermes is already
# running. So there is no second agent and no second API key: qwen3.8-27b drives
# it, and nothing here talks to Browser Use Cloud.
#
# Since 0.13.x it speaks CDP directly (cdp-use + browser-harness) with no
# Playwright anywhere in its dependency tree, which sidesteps the usual NixOS
# problem where Playwright's downloaded browsers are dynamically linked against
# libraries that do not exist here. It never downloads a browser at all - it
# attaches to one you are already running, which is what hermes-browser below
# provides.
#
# ── Pinning ──────────────────────────────────────────────────────────────────
# Hermes' _find_cli() probes $HERMES_HOME/bin, then PATH, then ~/.local/bin,
# then falls back to `uvx browser-use`. That uvx fallback is the easy route and
# is what upstream expects, but it resolves browser-use from PyPI at runtime -
# unpinned, and silently moving with new releases. So the CLI is built here
# instead, from assets/browser-use/uv.lock, and lands on the agent's PATH where
# the second probe finds it. Nothing reaches PyPI at run time.
#
# uv2nix/pyproject-nix/pyproject-build-systems come from hermes-agent's own
# inputs rather than being declared in modules/flake-inputs.nix. Deliberate:
# those three have to be mutually version-compatible, hermes-agent already
# pins a working triple and builds its own venv with it against this same
# nixpkgs, and it is an input of this config regardless. Three more top-level
# inputs to hand-align on every bump is the more fragile option, not the less.
# If hermes-agent ever drops them, declare them here and add the follows.
#
# Only browser-use and browser-harness are linked out of the venv. The venv's
# own bin/ carries ~35 entries - python, python3, openai, httpx, idna, tqdm,
# mcp, websockets, distro, plus `bu` and a bare `browser` - and extraPackages
# goes straight onto the agent's PATH, where several of those would shadow real
# tools.
#
# Verified end to end on this machine before being written: uvx resolved the
# CLI, browser-harness attached to a nixpkgs chromium over CDP, and
# `goto_url("https://example.com"); print(page_info())` returned
# {'url': 'https://example.com/', 'title': 'Example Domain', ...}.
{ den, inputs, ... }:
{
  den.aspects.browser-use.homeManager =
    { lib, pkgs, ... }:
    let
      # See the header for why these are reached through hermes-agent.
      inherit (inputs.hermes-agent.inputs) uv2nix pyproject-nix pyproject-build-systems;

      # browser-use requires >=3.11,<4; assets/browser-use/pyproject.toml
      # narrows the lock to 3.12, so this has to match or mkVirtualEnv resolves
      # against markers the lock was never solved for.
      python = pkgs.python312;

      workspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ../../assets/browser-use;
      };

      # "wheel" rather than "sdist": this dependency set is overwhelmingly
      # binary wheels (pillow, protobuf, yarl, pydantic-core), and preferring
      # sdists would mean compiling them for no benefit.
      pythonSet = (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          (workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
        ]
      );

      browserUseVenv = pythonSet.mkVirtualEnv "browser-use-env" workspace.deps.default;

      browser-use = pkgs.runCommand "browser-use" { } ''
        mkdir -p $out/bin
        ln -s ${browserUseVenv}/bin/browser-use $out/bin/browser-use
        ln -s ${browserUseVenv}/bin/browser-harness $out/bin/browser-harness
      '';

      # Chrome's conventional debugging port. Nothing else in this config binds
      # it, and hermes-browser refuses to start a second instance on top of a
      # live one.
      port = 9222;

      hermes-browser = pkgs.writeShellApplication {
        name = "hermes-browser";
        runtimeInputs = [
          pkgs.chromium
          pkgs.coreutils
          pkgs.curl
          pkgs.procps
          pkgs.util-linux # setsid
        ];
        text = builtins.readFile ../../assets/scripts/hermes-browser.sh;
      };
    in
    {
      home.packages = [ hermes-browser ];

      services.hermes-agent = {
        # The pinned CLI, found by the PATH probe in _find_cli(). The unit's
        # PATH is an explicit replacement rather than an extension of the
        # interactive profile PATH (homeManagerModules.nix unitPath), so the
        # gateway cannot see this unless it is listed here - something on the
        # user profile alone would work from a terminal and mysteriously not
        # from Discord.
        extraPackages = [ browser-use ];

        environment = {
          # browser-harness ships telemetry ON by default - it mints an install
          # id and posts to PostHog EU. Off, to match the rest of this stack.
          # Set through the environment rather than `browser-use telemetry
          # disable`, which writes a stateful opt-out to
          # ~/.config/browser-harness/telemetry.json that nothing here manages.
          ANONYMIZED_TELEMETRY = "false";
        };

        settings = {
          # Flips browser_exec on in place of the built-in browser tools. Only
          # the literal "browser-use" does this - the previous "off" merely
          # silenced the "CLI not found" notice.
          browser.backend = "browser-use";

          # Points Browser Use at the local Chromium instead of letting
          # browser-harness hunt for one, and instead of a cloud provider.
          # _get_cdp_override() reads this (or the BROWSER_CDP_URL env var,
          # which is what `/browser connect` sets at runtime).
          #
          # When the browser is not running this endpoint is simply dead and
          # browser_exec fails for that call - it does not stall startup, since
          # Hermes deliberately uses a non-probing read of this key for tool
          # gating. Start it with `hermes-browser`.
          browser.cdp_url = "http://127.0.0.1:${toString port}";
        };
      };
    };
}
