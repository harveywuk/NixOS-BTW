# papi-ux/polaris: self-hosted GameStream host (Moonlight/Nova-compatible).
# npm-deps hash for the from-source build was stale on upstream master until
# https://github.com/papi-ux/polaris/pull/392 merged it.
{ den, inputs, ... }:
{
  den.aspects.polaris =
    { ... }:
    {
      nixos =
        { ... }:
        {
          # nixpkgs already ships services.polaris for agersant/polaris (an
          # unrelated music server) under the exact same option namespace.
          # Drop it so this flake's services.polaris (GameStream host) options
          # don't collide with it.
          disabledModules = [ "services/misc/polaris.nix" ];
          imports = [ inputs.polaris.nixosModules.polaris ];
          services.polaris = {
            enable = true;
            users = [ "mrpickles" ];
          };
        };
    };
}
