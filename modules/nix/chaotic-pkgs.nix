{ inputs, ... }:
{
  # Chaotic's package set evaluated against chaotic's OWN nixpkgs pin rather
  # than ours, exposed to other modules as `chaoticPkgs`.
  #
  # Why this exists: chaotic's CI builds nyx-cache.chaotic.cx against its own
  # nixpkgs. Taking a chaotic package from pkgs.* routes it through chaotic's
  # overlay, which re-evaluates it against OUR nixpkgs, changing every hash and
  # missing the cache entirely. That is what made each flake bump rebuild the
  # CachyOS LTO kernel from source (~1h) - and, via nvidia_cachyos, a second
  # uncached kernel on top of it.
  #
  # allowUnfree is required for nvidia_cachyos. It is an eval-time assertion
  # only and does not enter any derivation, so the store paths produced here
  # are byte-identical to the ones chaotic's CI pushed.
  #
  # Only worth using for things chaotic's CI actually caches; small leaf
  # packages (e.g. ananicy-rules-cachyos) are fine straight from pkgs.*.
  den.aspects.chaotic-pkgs.nixos =
    { pkgs, ... }:
    {
      _module.args.chaoticPkgs = import inputs.chaotic.inputs.nixpkgs {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.allowUnfree = true;
        overlays = [ inputs.chaotic.overlays.default ];
      };
    };
}
