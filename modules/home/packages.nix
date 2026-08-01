{ den, inputs, ... }:
{
  den.aspects.packages.homeManager =
    {
      pkgs,
      ...
    }:
    {
      # high-tide crashes on first launch if ~/.cache/high-tide doesn't
      # already exist, since it calls mkdir() without parents=True.
      systemd.user.tmpfiles.rules = [
        "d %C/high-tide/images 0755 - - -"
      ];

      home.packages = with pkgs; [
        appimage-run
        asciinema
        blueman
        cmatrix
        comma
        devenv
        evtest
        ffmpeg
        file-roller
        fragments
        gh-dash
        gpu-screen-recorder
        grim
        gvfs
        home-manager
        hyprpicker
        hyprpwcenter
        hyprshutdown
        hyprsysteminfo
        kdePackages.okular
        kitty-themes
        lazyjj
        libsecret
        inputs.nix-versions.packages.${pkgs.stdenv.hostPlatform.system}.default
        obsidian
        oculante
        onlyoffice-desktopeditors
        pinta
        protonup-qt
        redact
        seahorse
        slurp
        socat
        wayfreeze
        wl-clipboard
      ];
    };
}
