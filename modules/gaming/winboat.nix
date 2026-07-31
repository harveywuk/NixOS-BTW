{ den, ... }:
{
  den.aspects.winboat =
    { ... }:
    {
      nixos =
        { ... }:
        {
          # WinBoat runs its Windows VM inside a Docker container
          virtualisation.docker.enable = true;
        };

      homeManager =
        { pkgs, ... }:
        {
          home.packages = with pkgs; [ winboat ];
        };
    };
}
