{ den, ... }:
{
  den.aspects.pics.homeManager =
    {
      config,
      lib,
      ...
    }:
    let
      picsDir = "${config.home.homeDirectory}/pics";
      wallpapersDir = "${config.home.homeDirectory}/nix/assets/wallpapers";
    in
    {
      # Wallpapers live in this repo under assets/wallpapers, symlinked to
      # ~/pics since that's the path Noctalia's wallpaper picker expects.
      home.activation.linkPicsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -e "${picsDir}" ]; then
          $DRY_RUN_CMD ln -s "${wallpapersDir}" "${picsDir}"
        fi
      '';
    };
}
