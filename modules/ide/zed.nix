{ ... }:
{
  den.aspects.zed.homeManager =
    { pkgs, ... }:
    {
      programs.zed-editor = {
        enable = true;
        package = pkgs.zed-editor;
        extensions = [ "dracula" ];
        userSettings.theme = "Dracula";
      };
    };
}
