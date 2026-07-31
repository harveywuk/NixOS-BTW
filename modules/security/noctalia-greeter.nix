{ den, inputs, ... }:
{
  den.aspects.noctalia-greeter =
    { host, user, ... }:
    {
      nixos =
        { pkgs, lib, ... }:
        {
          imports = [
            (inputs.noctalia-greeter.nixosModules.default or inputs.noctalia-greeter)
          ];
          programs = {
            noctalia-greeter = {
              enable = true;
              package = inputs.noctalia-greeter.packages.${pkgs.stdenv.hostPlatform.system}.default;
              greeter-args = "";
              settings = {
                user = {
                  default = user.userName;
                };
                output = {
                  layout = lib.concatStringsSep "; " (
                    lib.optionals (builtins.hasAttr "monitors" host) (
                      lib.optional (builtins.hasAttr "main" host.monitors) "${host.monitors.main.name}:${
                        builtins.replaceStrings [ "x" ] [ "," ] host.monitors.main.position
                      }"
                      ++ lib.optional (builtins.hasAttr "secondary" host.monitors) "${host.monitors.secondary.name}:${
                        builtins.replaceStrings [ "x" ] [ "," ] host.monitors.secondary.position
                      }"
                    )
                  );
                };
                appearance = {
                  # "Synced" lets Sync Now (Noctalia Shell settings) push the
                  # palette/wallpaper here; a hardcoded scheme name would win
                  # over Sync every time since declarative keys take priority.
                  scheme = "Synced";
                };
                cursor = {
                  theme = "Bibata-Modern-Ice";
                  size = 32;
                };
              };
            };
          };
          # noctalia-greeter only takes a theme name (no package option), so the
          # cursor theme must be discoverable system-wide for greetd to find it.
          environment.systemPackages = [ pkgs.bibata-modern-ice-hyprcursor ];
          security.pam.services.greetd.enableGnomeKeyring = true;
        };
    };
}
