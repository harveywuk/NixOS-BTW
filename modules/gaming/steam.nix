{ den, inputs, ... }:
{
  den.aspects.steam =
    { host, ... }:
    {
      nixos =
        { pkgs, ... }:
        let
          mainMon = host.monitors.main or { };
          builtinMon = host.monitors.builtin or { };

          primaryDisplay = mainMon.name or builtinMon.name or "";
        in
        {
          programs.steam = {
            enable = true;
            remotePlay.openFirewall = true;
            dedicatedServer.openFirewall = true;
            localNetworkGameTransfers.openFirewall = true;
            extraCompatPackages = with pkgs; [
              proton-ge-bin
              #inputs.nix-proton-cachyos.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos
            ];
          };
          environment.sessionVariables = {
            # Proton settings
            DXVK_HUD = "0";
            DXVK_HDR = "1";
            PROTON_ENABLE_HDR = "1";
            PROTON_USE_NTSYNC = "1";
            PROTON_XESS_UPGRADE = "1";
            # Upgrade bundled DLSS DLLs — only honored by proton-cachyos's
            # protonfixes, since mainline Proton can't redistribute NVIDIA's
            # closed-source DLLs the way it does with FSR/XeSS
            PROTON_DLSS_UPGRADE = "1";
            # Force NVAPI on for titles Proton hasn't allow-listed, and expose
            # the real adapter to NVAPI queries so DLSS/Reflex are detected
            PROTON_ENABLE_NVAPI = "1";
            DXVK_NVAPIHACK = "0";
            # Expose DXR ray tracing to DX12 titles translated through VKD3D-Proton
            VKD3D_CONFIG = "dxr";
            # Primary display for Proton Wayland driver
            WAYLANDDRV_PRIMARY_DISPLAY = primaryDisplay;
          };
        };

      homeManager =
        { pkgs, ... }:
        let
          # chaotic-nyx's proton-cachyos ships its files under bin/ instead of the
          # package root, so Steam can't find compatibilitytool.vdf there; re-expose
          # it a level up so it shows up as a compat tool.
          protonCachyOSFixed = pkgs.runCommand "proton-cachyos-fixed" { } ''
            mkdir -p $out
            for f in ${pkgs.proton-cachyos_x86_64_v3}/bin/*; do
              ln -s "$f" "$out/$(basename "$f")"
            done
          '';
        in
        {
          home.packages = with pkgs; [
            inputs.scopebuddy.packages.${pkgs.stdenv.hostPlatform.system}.default
            inputs.scopebuddy-gui.packages.${pkgs.stdenv.hostPlatform.system}.default
            # gamescope itself comes from den.aspects.polaris (gamescope-polaris,
            # an HDR-patched build) - a plain gamescope here collides with it in
            # home.packages (same wrapped binary path).
            protontricks
            vulkan-tools
            sgdboop
            # GTK theme style for Steam; run `adwsteamgtk` manually to apply
            adwsteamgtk
          ];

          # Steam's STEAM_EXTRA_COMPAT_TOOLS_PATHS (used by programs.steam.extraCompatPackages)
          # only honors the first colon-separated entry in this Steam client build, so anything
          # beyond proton-ge-bin there silently never gets scanned. Symlinking extra compat tools
          # directly into compatibilitytools.d sidesteps that — Steam scans it as real
          # subdirectories, so this is also the place to add future Proton builds.
          home.file.".local/share/Steam/compatibilitytools.d/Proton-CachyOS".source = protonCachyOSFixed;
        };
    };
}
