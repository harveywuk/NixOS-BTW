{ den, ... }:
{
  den.aspects.starship = {
    homeManager = {
      programs.starship = {
        enable = true;
        enableFishIntegration = true;
        enableInteractive = true;
        settings = {
          format = "$username$hostname$directory$vcsh$git_branch$git_commit$git_state$git_metrics$git_status$hg_branch$hg_state$all$line_break$character\n";
          character = {
            success_symbol = "[❯](green)";
            error_symbol = "[✖](red)";
            vimcmd_symbol = "[](green)";
          };

          # Official Dracula palette: https://draculatheme.com/starship
          palette = "dracula";
          palettes.dracula = {
            background = "#282a36";
            current_line = "#44475a";
            foreground = "#f8f8f2";
            comment = "#6272a4";
            cyan = "#8be9fd";
            green = "#50fa7b";
            orange = "#ffb86c";
            pink = "#ff79c6";
            purple = "#bd93f9";
            red = "#ff5555";
            yellow = "#f1fa8c";
          };
        };
      };
    };
  };
}
