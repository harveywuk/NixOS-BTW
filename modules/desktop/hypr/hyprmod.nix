{ inputs, ... }:
{
  den.aspects.hyprmod.homeManager =
    { pkgs, ... }:
    {
      home.packages = [
        inputs.hyprmod.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };
}
