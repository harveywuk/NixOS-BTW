{ den, ... }:
{
  den.aspects.nautilus = {
    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.nautilus ];

        # Needed for thumbnail previews, network locations (gvfs) etc.
        services.gvfs.enable = true;
        services.tumbler.enable = true;

        # "Open Terminal Here" context menu entry — Nautilus equivalent
        # of Thunar's custom UCA action for the same thing.
        programs.nautilus-open-any-terminal = {
          enable = true;
          terminal = "kitty";
        };
      };

    homeManager =
      { pkgs, ... }:
      {
        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            # Images
            "image/png" = "oculante.desktop";
            "image/jpeg" = "oculante.desktop";
            "image/jpg" = "oculante.desktop";
            "image/gif" = "oculante.desktop";
            "image/webp" = "oculante.desktop";
            "image/bmp" = "oculante.desktop";
            "image/tiff" = "oculante.desktop";
            "image/svg+xml" = "oculante.desktop";

            # PDFs and documents
            "application/pdf" = "okularApplication_pdf.desktop";

            # Web browser
            "text/html" = "zen.desktop";
            "x-scheme-handler/http" = "zen.desktop";
            "x-scheme-handler/https" = "zen.desktop";
            "x-scheme-handler/about" = "zen.desktop";
            "x-scheme-handler/unknown" = "zen.desktop";

            # Text files
            "text/plain" = "hx.desktop";
            "text/markdown" = "hx.desktop";
            "text/x-shellscript" = "hx.desktop";
            "text/x-python" = "hx.desktop";
            "text/x-csrc" = "hx.desktop";
            "text/x-c++src" = "hx.desktop";
            "text/x-java" = "hx.desktop";
            "text/javascript" = "hx.desktop";
            "application/javascript" = "hx.desktop";
            "text/css" = "hx.desktop";
            "application/json" = "hx.desktop";
            "application/xml" = "hx.desktop";
            "text/xml" = "hx.desktop";
            "text/x-yaml" = "hx.desktop";
            "application/x-yaml" = "hx.desktop";
            "text/x-rust" = "hx.desktop";
            "text/x-go" = "hx.desktop";
            "application/x-shellscript" = "hx.desktop";
            "text/x-lua" = "hx.desktop";
            "text/x-makefile" = "hx.desktop";
            "text/x-log" = "hx.desktop";
            "application/toml" = "hx.desktop";
            "text/x-nix" = "hx.desktop";

            # Videos
            "video/mp4" = "mpv.desktop";
            "video/x-matroska" = "mpv.desktop";
            "video/webm" = "mpv.desktop";
            "video/mpeg" = "mpv.desktop";
            "video/x-msvideo" = "mpv.desktop";
            "video/quicktime" = "mpv.desktop";
            "video/x-flv" = "mpv.desktop";

            # Audio
            "audio/mpeg" = "mpv.desktop";
            "audio/mp4" = "mpv.desktop";
            "audio/x-wav" = "mpv.desktop";
            "audio/flac" = "mpv.desktop";
            "audio/ogg" = "mpv.desktop";
            "audio/x-vorbis+ogg" = "mpv.desktop";
            "audio/x-opus+ogg" = "mpv.desktop";

            # Archives
            "application/zip" = "org.gnome.FileRoller.desktop";
            "application/x-tar" = "org.gnome.FileRoller.desktop";
            "application/x-gzip" = "org.gnome.FileRoller.desktop";
            "application/x-bzip2" = "org.gnome.FileRoller.desktop";
            "application/x-7z-compressed" = "org.gnome.FileRoller.desktop";
            "application/x-rar" = "org.gnome.FileRoller.desktop";

            # File manager
            "inode/directory" = "org.gnome.Nautilus.desktop";
          };
        };

        dconf.settings = {
          "org/gtk/settings/file-chooser" = {
            show-hidden = true;
          };
        };

        xdg.dataFile."applications/hx.desktop".text = ''
          [Desktop Entry]
          Name=Helix
          Exec=kitty -e hx %F
          Terminal=false
          Type=Application
          Keywords=Text;editor;
          Icon=hx
          Categories=Utility;TextEditor;
          StartupNotify=false
        '';
      };
  };
}
