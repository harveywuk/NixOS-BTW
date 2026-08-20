# A selectable wayland-sessions entry ("Steam (gamescope)") for
# noctalia-greeter/greetd - boots straight into Steam Big Picture inside a
# gamescope compositor instead of Hyprland, Deck-style. Separate from
# den.aspects.polaris's own gamescope usage (that one streams a session to a
# remote client; this one drives the physical monitor directly), so the two
# never run at once in practice, but both ultimately shell out to `steam
# -gamepadui` in their own owned gamescope instance.
{ den, ... }:
{
  den.aspects.steam-gamescope-session =
    { host, ... }:
    {
      nixos =
        { pkgs, lib, ... }:
        let
          mainMon = host.monitors.main or { };
          modeParts = lib.splitString "@" (mainMon.mode or "1920x1080@60");
          resolution = lib.elemAt modeParts 0;
          refresh = lib.elemAt modeParts 1;
          resParts = lib.splitString "x" resolution;
          width = lib.elemAt resParts 0;
          height = lib.elemAt resParts 1;
          supportsHdr = mainMon.supports_hdr or false;
          supportsVrr = (mainMon.vrr or 0) > 0;

          sessionScript = pkgs.writeShellScriptBin "steam-gamescope-session" ''
            exec ${pkgs.gamescope-polaris}/bin/gamescope \
              -W ${width} -H ${height} -r ${refresh} \
              ${lib.optionalString supportsVrr "--adaptive-sync"} \
              ${lib.optionalString supportsHdr "--hdr-enabled"} \
              -f -- steam -gamepadui -steamos3 -steamdeck
          '';

          sessionEntry =
            pkgs.writeTextDir "share/wayland-sessions/steam-gamescope.desktop" ''
              [Desktop Entry]
              Name=Steam (gamescope)
              Comment=Boots directly into Steam Big Picture inside gamescope
              Exec=${sessionScript}/bin/steam-gamescope-session
              Type=Application
            ''
            // {
              providedSessions = [ "steam-gamescope" ];
            };
        in
        {
          services.displayManager.sessionPackages = [ sessionEntry ];
        };
    };
}
