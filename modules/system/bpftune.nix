{ den, ... }:
{
  den.aspects.bpftune.nixos =
    { ... }:
    {
      services.bpftune.enable = true;
    };
}
