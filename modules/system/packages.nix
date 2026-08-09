{ den, inputs, ... }:
{
  den.aspects.systempackages.nixos =
    { pkgs, ... }:
    {
      # profile-sync-daemon needs its service enabled to actually sync
      # browser profiles to tmpfs — just having the binary does nothing.
      services.psd.enable = true;

      # System wide packages
      environment.systemPackages = with pkgs; [
        bc
        # bind's outputsToInstall is [out dnsutils host], so this already
        # provides dig/delv/nslookup/host - a separate `dig` entry is the
        # same derivation again.
        bind
        bluetui
        bpftune
        brightnessctl
        cachix
        choose
        claude-code
        ddcutil
        dust
        fbset
        fd
        file
        gnupg
        high-tide
        hydra-check
        iperf3
        killall
        libnotify
        lsof
        mediainfo
        mtr
        nix-converter
        nixfmt
        nixpkgs-review
        ncdu
        nurl
        nvd
        pciutils
        playerctl
        profile-sync-daemon
        pulsar-mouse-linux
        ripgrep
        sd
        swappy
        traceroute
        tree
        treefmt
        tree-sitter
        unzip
        usbutils
        via
        wget
        whois
        # Used by the hypr resume hook and screen-toggle.sh: XWayland Steam
        # games read xrandr primary for resolution.
        xrandr
        zip
      ];
    };
}
