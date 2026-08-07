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
        bind
        bluetui
        bluez
        bpftune
        brightnessctl
        cachix
        choose
        claude-code
        cron
        dig
        ddcutil
        dust
        fbset
        fd
        file
        gnupg
        gzip
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
        procps
        profile-sync-daemon
        pulsar-mouse-linux
        ripgrep
        rtkit
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
        xrandr
        xwayland
        zip
      ];
    };
}
