{ ... }:
{
  den.aspects.vscode.homeManager =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.vscode ];
    };
}
