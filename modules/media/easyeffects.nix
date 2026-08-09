{ den, ... }:
{
  den.aspects.easyeffects.homeManager =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      xdg.configFile = {
        "easyeffects/autoload/easyeffectsrc".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix/assets/easyeffects/autoload/easyeffectsrc";
        "easyeffects/autoload/microphone.json".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix/assets/easyeffects/autoload/microphone.json";
        "easyeffects/autoload/speexrc".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix/assets/easyeffects/autoload/speexrc";
        "easyeffects/autoload/equalizerrc".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix/assets/easyeffects/autoload/equalizerrc";
      };

      # EasyEffects 8.x uses Qt/KDE config instead of dconf
      # Note: Qt version doesn't have system tray support - feature was removed in Qt port
      # Settings are managed via ~/.config/easyeffects/autoload/easyeffectsrc and db/easyeffectsrc
      services.easyeffects.enable = true;
    };
}
