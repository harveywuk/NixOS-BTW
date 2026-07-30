{ den, ... }:
{
  den.aspects.usb = {
    nixos =
      { pkgs, ... }:
      {
        services = {
          udisks2.enable = true;
        };
      };
  };
}
