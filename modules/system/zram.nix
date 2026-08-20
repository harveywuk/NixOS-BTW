# Compressed RAM-backed swap, ahead of the disk swap partition in priority so
# it absorbs swap activity first and only spills to disk under real memory
# pressure.
{ den, ... }:
{
  den.aspects.zram.nixos = {
    zramSwap = {
      enable = true;
      priority = 100;
    };
  };
}
