{ den, inputs, ... }:
{
  den.aspects.stylix = {
    nixos =
      { pkgs, lib, ... }:
      {
        imports = [ inputs.stylix.nixosModules.stylix ];
        stylix = {
          enable = true;
          polarity = "dark";
          base16Scheme = "${pkgs.base16-schemes}/share/themes/dracula.yaml";

          targets.kmscon.enable = false;
          targets.qt = {
            enable = true;
            platform = lib.mkForce "qtct";
          };
          targets.gtk.enable = true;
          targets.gtksourceview.enable = false;

          icons = {
            enable = true;
            light = "WhiteSur-light";
            dark = "WhiteSur-dark";
            package = pkgs.whitesur-icon-theme;
          };

          cursor = {
            name = "Bibata-Modern-Ice";
            package = pkgs.bibata-modern-ice-hyprcursor;
            size = 32;
          };

          image = "${inputs.self}/assets/wallpapers/ultrawide/wallhaven-5gqrp3.jpg";

          fonts = {
            serif = {
              name = "Roboto";
            };

            sansSerif = {
              name = "Inter";
            };

            monospace = {
              name = "NeonMono";
            };

            emoji = {
              name = "Noto Color Emoji";
            };

            sizes = {
              terminal = 16;
              applications = 13;
            };
          };
        };
      };

    homeManager =
      { lib, ... }:
      {
        stylix = {
          autoEnable = true;
          targets = {
            # Force qtct styling for qt dialogs
            qt = {
              platform = lib.mkForce "qtct";
              standardDialogs = "xdgdesktopportal";
            };
            # Disable the following, we already have more intricate themes for these
            bat.enable = false;
            cava.enable = false;
            helix.enable = false;
            hyprland.enable = false;
            kitty.enable = false;
            lazygit.enable = false;
            noctalia.enable = false;
            obsidian.enable = false;
            opencode.enable = false;
            starship.enable = false;
            vesktop.enable = false;
            yazi.enable = false;
            zed.enable = false;
          };
        };
      };
  };
}
