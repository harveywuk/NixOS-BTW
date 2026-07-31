{ den, ... }:
{
  den.aspects.coolercontrol.nixos = {
    programs.coolercontrol.enable = true;
  };
}
