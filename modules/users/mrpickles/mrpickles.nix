{ den, lib, ... }:
{
  den.aspects.mrpickles =
    { host, ... }:
    {
      includes = [
        # Shell tools
        den.aspects.bat
        den.aspects.btop
        den.aspects.direnv
        den.aspects.delta
        den.aspects.fastfetch
        den.aspects.fzf
        den.aspects.git
        den.aspects.helix
        den.aspects.jq
        den.aspects.just
        den.aspects.kitty
        den.aspects.lazygit
        den.aspects.lsd
        den.aspects.mcp
        den.aspects.nh
        den.aspects.nix-index
        den.aspects.opencode
        den.aspects.payrespects
        den.aspects.starship
        # den.aspects.pure
        den.aspects.tealdeer
        den.aspects.yazi
        den.aspects.zed
        den.aspects.zoxide
        den.aspects.fish

        # Desktop
        den.aspects.de
        den.aspects.fonts
        den.aspects.xdg
        den.aspects.stylix
        den.aspects.noctalia
        den.aspects.flatpak
        den.aspects.clipboard
        den.aspects.cursor
        den.aspects.gtk
        den.aspects.hyprland
        den.aspects.satty
        den.aspects.nautilus

        # Services (user-level)
        den.aspects.gnomekeyring
        den.aspects.pipewire
        den.aspects.usb

        # Home
        den.aspects.common
        den.aspects.files
        den.aspects.packages

        # Media
        den.aspects.cava
        den.aspects.easyeffects
        den.aspects.mpv
        # Wallpapers: symlinks assets/wallpapers in this repo to ~/pics,
        # which is the path Noctalia's wallpaper picker expects. No remote
        # fetch involved - see modules/media/pics.nix.
        den.aspects.pics

        # Communication
        den.aspects.vesktop

        # AI agent
        den.aspects.hermes-agent
        # Hermes' memory provider - depends on hermes-agent above for both the
        # plugin path and the interpreter it runs on.
        den.aspects.mnemosyne
        # Hermes' browser backend - adds uv to the agent's PATH and the
        # hermes-browser launcher it drives over CDP.
        den.aspects.browser-use
        # Named agent teammates as Hermes profiles. Depends on hermes-agent
        # for HERMES_HOME and on mnemosyne for the memory plugin it links
        # into each bot, so it must come after both.
        den.aspects.hermes-bots
      ]
      ++ lib.optionals (host.isGaming or false) [
        # Gated on host.isGaming (set per-host in modules/hosts.nix) so a
        # non-gaming host does not pull Steam and friends. These used to sit
        # in the unconditional list above while this block sat empty, which
        # meant the flag existed but decided nothing.
        den.aspects.steam
        den.aspects.mangohud
        den.aspects.winboat
        den.aspects.polaris
        den.aspects.gamemode
        den.aspects.steam-gamescope-session
      ];

      nixos =
        { pkgs, lib, ... }:
        {
          users.users.mrpickles = {
            description = "mrpickles";
            shell = lib.mkForce pkgs.fish;
            # Keeps the systemd --user manager (and hermes-agent's gateway
            # service in it) running after logout - see modules/ai/hermes-agent.nix.
            linger = true;
            extraGroups = [
              "networkmanager"
              "audio"
              "video"
              "input"
              "libvirtd"
              "dialout"
              "wheel"
              "docker"
            ];
          };
        };
    };
}
