{ den, ... }:
{
  den.aspects.bat.homeManager =
    { ... }:
    {
      programs.bat = {
        enable = true;
        # Dracula ships as a built-in bat theme: https://draculatheme.com
        config.theme = "Dracula";
      };

      programs.zsh.shellAliases.cat = "bat";
    };
}
