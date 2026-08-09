{ den, ... }:
{
  den.aspects.gtk =
    { host, user, ... }:
    {
      homeManager =
        {
          pkgs,
          osConfig,
          lib,
          ...
        }:
        let
          systemMounts = [
            "/"
            "/boot"
            "/nix"
            "/proc"
            "/sys"
            "/dev"
            "/run"
            "/tmp"
          ];
          # Dynamically add bookmarks for non-system mounts
          extraFsBookmarks = map (mp: "file://${mp}") (
            builtins.filter (mp: !builtins.elem mp systemMounts) (builtins.attrNames osConfig.fileSystems)
          );

          defaultBookmarks = [
            "file:///home/${user.userName}/.config"
            "file:///home/${user.userName}/.local/share/Trash/files Trash"
            "file:///home/${user.userName}/3D"
            "file:///home/${user.userName}/Downloads"
            "file:///home/${user.userName}/Screenshots"
            "file:///home/${user.userName}/Videos"
            "file:///home/${user.userName}/dev"
            "file:///home/${user.userName}/gamedev"
            "file:///home/${user.userName}/nix"
            "file:///home/${user.userName}/pics"
            "file:///synology"
          ]
          ++ extraFsBookmarks;
        in
        {
          # Force Home Manager to overwrite existing GTK files
          xdg.configFile."gtk-3.0/settings.ini".force = true;
          xdg.configFile."gtk-4.0/settings.ini".force = true;
          xdg.configFile."gtk-4.0/gtk.css".force = true;

          # Seed gtk-3.0/bookmarks ONCE as a plain file, rather than using
          # the built-in gtk.gtk3.bookmarks option (which hard-symlinks the
          # file into the Nix store on every rebuild, silently discarding
          # anything added or removed via Nautilus's sidebar).
          home.activation.seedGtkBookmarks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            BOOKMARKS_FILE="$HOME/.config/gtk-3.0/bookmarks"
            if [ ! -e "$BOOKMARKS_FILE" ]; then
              mkdir -p "$(dirname "$BOOKMARKS_FILE")"
              printf '%s\n' ${lib.escapeShellArgs defaultBookmarks} > "$BOOKMARKS_FILE"
            fi
          '';

          gtk = {
            enable = true;
            gtk3 = {
              extraConfig = {
                gtk-application-prefer-dark-theme = 1;
              };
            };
            gtk4 = {
              extraConfig = {
                gtk-application-prefer-dark-theme = 1;
              };
            };
          };
        };
    };
}
