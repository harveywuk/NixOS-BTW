# All flake inputs are declared here so flake-file can regenerate flake.nix.
# Run `nix run .#write-flake` after adding or changing any input.
{ lib, ... }:
{
  flake-file.inputs = {
    den.url = "github:denful/den/refs/tags/v0.18.0";
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    # Deliberately NOT following nixpkgs. Chaotic's CI builds its binary
    # cache (nyx-cache.chaotic.cx) against its own nixpkgs pin, so making
    # it follow ours re-hashes every chaotic derivation and misses the
    # cache - which meant rebuilding the CachyOS LTO kernel from source on
    # every bump (~1h). The cost is a second nixpkgs in the lock.
    #
    # Only pays off for things consumed via inputs.chaotic.legacyPackages;
    # anything taken from pkgs.* still goes through chaotic's overlay and
    # is therefore still built against our nixpkgs. See kernel.nix.
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    # Same reasoning as chaotic above: not following nixpkgs so its own CI
    # (Attic cache at attic.xuyh0120.win/lantian) stays a cache hit instead
    # of rebuilding kernels from source on every bump. `release` branch for
    # stability, per upstream's own recommendation. See kernel.nix - used
    # for a real BORE scheduler build, since chaotic's own
    # linuxPackages_cachyos-lto-znver4 silently drops SCHED_BORE (its
    # "cachyos" cpuSched preset never applies the bore-cachy.patch, only
    # the config flag - see prepare.nix upstream).
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    # Packages lemonade (the lemonade-sdk local AI server), plus the AMD NPU
    # stack we don't use. Same no-follows reasoning as chaotic and
    # nix-cachyos-kernel above, and here upstream is explicit about it: the
    # flake's overlay builds every derivation against its *own* nixpkgs pin
    # (`pinned` in its flake.nix), precisely so the input closure hashes match
    # both cache.nixos.org and nix-amd-ai.cachix.org. A `follows` re-hashes
    # them all and rebuilds the backends - including lemonade's Tauri desktop
    # app and its crates.io cargo-vendor fetch - from source.
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";
    bibata-hypr-src = {
      url = "github:rtgiskard/bibata_cursor";
      flake = false;
    };
    nix-proton-cachyos = {
      url = "github:kimjongbing/nix-proton-cachyos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
    };
    hypr-dynamic-cursors = {
      url = "github:VirtCode/hypr-dynamic-cursors";
      inputs.hyprland.follows = "hyprland";
    };
    # hyprcapture and hypr-edgehover dropped 2026-08-18: af0d014 split CWindow
    # into per-backend classes (Window.hpp moved under desktop/view/window/,
    # X11 fields moved onto backend(), m_isMapped/m_class/m_title/rounding
    # gone), which broke both plugins with no upstream fix, and this was the
    # only thing pinning Hyprland back at 6d43ce8. Not used often enough to
    # justify holding the pin - re-add both inputs (github:gfhdhytghd/
    # HyprCapture, github:gfhdhytghd/hypr-edgehover) once they catch up.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-versions = {
      url = "github:vic/nix-versions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pulsar-mouse-linux = {
      url = "github:harveywuk/pulsar-mouse-linux/feinmann8k-driver";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    polaris = {
      # CMake needs the third-party/* submodules (wayland-protocols,
      # moonlight-common-c, etc.). The github: fetcher ignores
      # ?submodules=1 entirely (GitHub's tarball API never includes
      # submodule content) - only the git+https: type fetcher honors it.
      url = "git+https://github.com/papi-ux/polaris?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Plain Python repo, not a flake - taken as a source input so flake.lock
    # tracks the pin. Packaged in modules/ai/mnemosyne.nix against python312,
    # which is the interpreter hermes-agent runs on.
    #
    # Pinned to a release tag rather than a branch: `main` currently carries
    # 4.0.0b1, a beta. Bump the tag deliberately - `nix flake update` cannot
    # move a tagged ref on its own.
    mnemosyne = {
      url = "github:mnemosyne-oss/mnemosyne/refs/tags/v3.15.1";
      flake = false;
    };
    # Ships its own flake with a NixOS module (services.hermes-webui) and a
    # package, so this is consumed directly rather than repackaged. Follows
    # nixpkgs: it is a pure-stdlib Python server whose only dependencies are
    # pyyaml and cryptography, so there is no CI-built cache to miss by
    # re-hashing it (unlike chaotic / nix-cachyos-kernel / nix-amd-ai above).
    hermes-webui = {
      url = "github:nesquena/hermes-webui";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia";
    };
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scopebuddy = {
      url = "github:OpenGamingCollective/ScopeBuddy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scopebuddy-gui = {
      url = "github:harveywuk/scopebuddy-gui-gtk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
