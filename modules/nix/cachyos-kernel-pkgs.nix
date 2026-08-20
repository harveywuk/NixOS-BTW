# Exposes xddxdd/nix-cachyos-kernel's package set as `cachyosKernelPkgs`,
# taken directly from its own flake outputs (already built against its own
# nixpkgs pin) rather than reconstructed via an overlay - see
# flake-inputs.nix for why this input doesn't follow our nixpkgs.
#
# Also trusts its Attic binary cache, so `boot.kernelPackages` in kernel.nix
# is a cache hit instead of a local LTO build.
{ inputs, ... }:
{
  den.aspects.cachyos-kernel-pkgs.nixos =
    { pkgs, ... }:
    {
      _module.args.cachyosKernelPkgs =
        inputs.nix-cachyos-kernel.legacyPackages.${pkgs.stdenv.hostPlatform.system};

      nix.settings = {
        extra-substituters = [ "https://attic.xuyh0120.win/lantian" ];
        extra-trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
      };
    };
}
