# hermes-webui (https://github.com/nesquena/hermes-webui) - a self-hosted web
# front end for Hermes with close to CLI parity: sessions, workspace file
# browser, voice input, and full agent tool execution rather than read-only
# monitoring.
#
# Upstream ships its own flake with a NixOS module and package, so this consumes
# `inputs.hermes-webui.nixosModules.default` directly instead of repackaging.
# The server is stdlib Python plus vanilla JS with no build step, and its only
# runtime dependencies are pyyaml and cryptography - all the heavy agent
# dependencies come from Hermes' own venv.
#
# ── Wiring it to a home-manager Hermes ───────────────────────────────────────
# Upstream's module is a NixOS (system) service that defaults to its own
# `hermes-webui` system user and /var/lib state, aimed at a system-level
# hermes-agent. This install is the other shape - Hermes runs as a
# `systemd --user` service with HERMES_HOME under ~/.hermes (see
# modules/ai/hermes-agent.nix) - so the service is pointed back at that:
# `user`/`group` are mrpickles, and `hermesHome` is the same directory the
# gateway uses. Both processes then read and write one set of sessions, cron
# jobs and memory, which is the entire point.
#
# The two agent hooks matter and are easy to get subtly wrong:
#
#   * agent.package infers HERMES_WEBUI_PYTHON from the package's
#     passthru.hermesVenv - i.e. the *sealed uv2nix venv* Hermes itself runs
#     on, which already has every agent dependency importable. Nothing is
#     installed at runtime.
#   * agent.dir has no passthru to infer from (hermes-agent exposes
#     hermesVenv but not hermesAgentDir), so it is set explicitly to the flake
#     source. The WebUI genuinely needs a source *checkout*, not just an
#     interpreter: it launches the gateway as
#     `$HERMES_WEBUI_PYTHON <agent.dir>/hermes_cli/main.py` (api/routes.py) and
#     puts that directory on sys.path. inputs.hermes-agent is exactly that
#     tree, and its config.py lookup accepts any path containing
#     hermes_cli/main.py.
#
# Note the WebUI also has an auto-install path that would `pip install` from
# agent.dir into the running interpreter. It never fires here: it is gated on
# the directory being owned by the invoking user, and a /nix/store path is
# owned by root. It logs a skip line and carries on, which is the desired
# outcome - the venv already has everything.
{ den, inputs, ... }:
{
  den.aspects.hermes-webui.nixos =
    { config, pkgs, ... }:
    let
      # ── Dracula skin ─────────────────────────────────────────────────────
      # Not hardcoded hex: these come from stylix, whose base16Scheme is
      # dracula.yaml (modules/desktop/stylix.nix), so the WebUI matches the rest
      # of the desktop from one source of truth. If that scheme ever changes,
      # this skin follows it and the name below stops being accurate - rename it
      # then rather than pinning colours here.
      c = config.lib.stylix.colors;

      # base16 has no hover slot, so the accent hover is the scheme's pink
      # (base0E) rather than an invented shade of the purple - a real colour
      # from the palette instead of a guess.
      #
      # Dracula is a dark palette with no light counterpart, so the skin
      # declares scheme = "dark": WebUI then applies the dark base while it is
      # selected, instead of mixing these tokens into light-mode surfaces. The
      # user's saved Light/Dark/System preference is left untouched.
      draculaSkin = pkgs.writeText "hermes-webui-dracula.js" ''
        // Registers a Dracula skin in Settings -> Appearance -> Skin.
        // Generated from stylix's base16 palette by modules/ai/hermes-webui.nix.
        (function () {
          if (typeof window.registerHermesSkin !== 'function') return;
          window.registerHermesSkin({
            name: 'Dracula',
            value: 'dracula',
            scheme: 'dark',
            colors: ['#${c.base00}', '#${c.base0F}', '#${c.base0E}'],
            tokens: {
              '--bg': '#${c.base00}',
              '--surface': '#${c.base01}',
              '--surface2': '#${c.base02}',
              '--surface-subtle': '#${c.base01}',
              '--sidebar': '#${c.base01}',
              '--sidebar-text': '#${c.base05}',

              '--text': '#${c.base05}',
              '--text2': '#${c.base04}',
              '--muted': '#${c.base03}',

              '--accent': '#${c.base0F}',
              '--accent2': '#${c.base0E}',
              '--accent3': '#${c.base0C}',
              '--accent-hover': '#${c.base0E}',
              '--accent-text': '#${c.base0F}',
              '--accent-contrast': '#${c.base00}',
              '--accent-rgb': '${c.base0F-rgb-r}, ${c.base0F-rgb-g}, ${c.base0F-rgb-b}',
              '--accent-bg': 'rgba(${c.base0F-rgb-r}, ${c.base0F-rgb-g}, ${c.base0F-rgb-b}, 0.10)',
              '--accent-bg-strong': 'rgba(${c.base0F-rgb-r}, ${c.base0F-rgb-g}, ${c.base0F-rgb-b}, 0.18)',

              '--border': '#${c.base02}',
              '--border2': '#${c.base01}',
              '--hover-bg': 'rgba(${c.base02-rgb-r}, ${c.base02-rgb-g}, ${c.base02-rgb-b}, 0.55)',

              '--code-bg': '#${c.base01}',
              '--code-text': '#${c.base05}',
              '--user-bubble': '#${c.base02}',
              '--assistant-bubble': '#${c.base01}',

              '--success': '#${c.base0B}',
              '--warning': '#${c.base09}',
              '--danger': '#${c.base08}',
              '--info': '#${c.base0C}',
              '--link': '#${c.base0D}'
            }
          });
        })();
      '';

      # EXTENSION_DIR must be an existing directory that WebUI serves assets
      # from; a store path is ideal here. Upstream's trust note warns against
      # pointing this at a user-writable directory, and /nix/store is
      # root-owned and read-only - extension JS runs with full session
      # authority, so nothing else should be able to drop a file in.
      extensionDir = pkgs.runCommand "hermes-webui-extensions" { } ''
        mkdir -p $out/hermes-dracula
        cp ${draculaSkin} $out/hermes-dracula/dracula.js
      '';
    in
    {
      imports = [ inputs.hermes-webui.nixosModules.default ];

      # A literal `HERMES_WEBUI_PASSWORD=...` line, matching the shape
      # environmentFiles expects. Not optional in practice: this UI executes
      # agent tools, including the terminal toolset, so an unauthenticated
      # instance is a local shell-as-mrpickles for anything that can reach the
      # port - which includes a page in a browser doing a cross-site POST, not
      # only other logged-in processes. Upstream leaves auth off by default.
      #
      # Read the generated password with:
      #   sops -d --extract '["hermes-webui-env"]' secrets/secrets.yaml
      sops.secrets."hermes-webui-env" = {
        owner = "mrpickles";
        mode = "0400";
      };

      services.hermes-webui = {
        enable = true;

        # Same user as the gateway, so the WebUI reads and writes the same
        # ~/.hermes state rather than a parallel copy under a system user.
        user = "mrpickles";
        group = "users";
        hermesHome = "/home/mrpickles/.hermes";

        agent = {
          package = config.home-manager.users.mrpickles.services.hermes-agent.package;
          # The flake source tree - see the header for why an interpreter alone
          # is not enough.
          dir = "${inputs.hermes-agent}";
        };

        # Loopback only, and openFirewall left at its default false. Reach it
        # from a phone over the Tailscale/SSH tunnel upstream documents rather
        # than by exposing the port.
        host = "127.0.0.1";
        port = 8787;

        environmentFiles = [ config.sops.secrets."hermes-webui-env".path ];

        # Neither of these is a protected runtime key, so they go through
        # extraEnvironment rather than needing module options.
        #
        # Setting EXTENSION_DIR overrides WebUI's managed default
        # (<stateDir>/extensions), which is where one-click gallery installs
        # land - so while this is set, the gallery cannot install into a
        # writable directory. That is an accepted trade for a Nix-managed
        # theme and nothing here uses the gallery; drop these two lines to get
        # it back.
        extraEnvironment = {
          HERMES_WEBUI_EXTENSION_DIR = "${extensionDir}";
          HERMES_WEBUI_EXTENSION_SCRIPT_URLS = "/extensions/hermes-dracula/dracula.js";
        };
      };
    };
}
