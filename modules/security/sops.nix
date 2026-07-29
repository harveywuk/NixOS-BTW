{ den, inputs, ... }:
{
  den.aspects.sops =
    { ... }:
    {
      nixos =
        { ... }:
        {
          imports = [ inputs.sops-nix.nixosModules.sops ];
          sops = {
            defaultSopsFile = inputs.self + "/secrets/secrets.yaml";
            age.keyFile = "/etc/sops/age/key.txt";
            useSystemdActivation = true;
            secrets = {
              "cachix" = {
                owner = "mrpickles";
                mode = "0400";
              };
              "github-pat" = {
                owner = "mrpickles";
                mode = "0400";
              };
            };
          };
        };
    };
}
