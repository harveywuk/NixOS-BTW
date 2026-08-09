{ den, ... }:
{
  den.aspects.fonts.nixos =
    { pkgs, ... }:
    {
      fonts.packages = with pkgs; [
        fira-sans
        inter
        roboto
        material-icons
        material-symbols
        nerd-fonts.jetbrains-mono
        nerd-fonts.symbols-only
        noto-fonts
        noto-fonts-color-emoji
        sn-pro
      ];
    };
}
