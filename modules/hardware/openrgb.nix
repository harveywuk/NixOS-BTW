{ den, ... }:
{
  den.aspects.openrgb.nixos =
    { pkgs, ... }:
    {
      services.hardware.openrgb = {
        enable = true;
        startupProfile = "wallpaper-gradient";
        package = pkgs.openrgb.withPlugins (
          with pkgs;
          [
            openrgb-plugin-effects
            openrgb-plugin-hardwaresync
          ]
        );
      };
    };
}
