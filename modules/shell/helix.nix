{ den, ... }:
{
  den.aspects.helix.homeManager =
    { ... }:
    {
      programs.helix = {
        enable = true;
        settings.theme = "dracula";
      };
    };
}
