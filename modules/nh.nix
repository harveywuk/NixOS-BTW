# Exposes flake apps for building each host with nh.
# e.g. `nix run .#nixos-btw`
{ den, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = den.lib.nh.denPackages { fromFlake = true; } pkgs;
    };
}
