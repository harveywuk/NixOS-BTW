{ den, ... }:
{
  den.aspects.easyeffects.homeManager =
    { ... }:
    {
      # EasyEffects 8.x (Qt port) keeps its settings in
      # ~/.config/easyeffects/db/easyeffectsrc, which the app owns and
      # rewrites itself - it is not managed from here.
      #
      # This used to symlink easyeffectsrc/equalizerrc/speexrc/microphone.json
      # into ~/.config/easyeffects/autoload/, but 8.x never reads those
      # filenames from autoload/ (that directory is for device -> preset
      # mappings), so all four were inert - which is what the old
      # "TODO doesn't seem to autoload" comment was actually describing.
      # Removed 2026-08-09; configure EasyEffects via its GUI instead.
      services.easyeffects.enable = true;
    };
}
