{ den, ... }:
{
  den.aspects.opencode.homeManager =
    { ... }:
    {
      programs = {
        # NOTE: Input/Output token costs
        # https://opencode.ai/docs/zen#pricing
        # The `oc` alias lives in fish.nix's shellAliases - it used to be set
        # via programs.zsh.initContent here, but zsh is not enabled and the
        # shell is fish, so it never took effect.
        opencode = {
          enable = true;
          enableMcpIntegration = true;

          commands = ../../assets/ai/commands;
          skills = ../../assets/ai/skills;

          settings = {
            default_agent = "build";

            permission = {
              external_directory = "ask";
              bash = {
                "git commit*" = "ask";
                "git pull*" = "ask";
                "git merge*" = "ask";
                "git push*" = "ask";
                "git reset*" = "ask";
                "git clean*" = "ask";
                "git branch -D*" = "ask";
                "git checkout --*" = "ask";
                "git restore*" = "ask";
                "git rebase*" = "ask";
                "git commit --amend*" = "ask";
              };
            };

            model = "opencode/big-pickle";
            enabled_providers = [ "opencode" ];
            tools.websearch = true;
            small_model = "opencode/big-pickle";
            share = "disabled";
          };
          tui = {
            theme = "dracula";
            scroll_speed = 3;
            scroll_acceleration = {
              enabled = true;
            };
            diff_style = "auto";
          };

          # Dracula palette: https://draculatheme.com/contribute
          themes.dracula.theme = {
            primary = "#bd93f9";
            secondary = "#ff79c6";
            accent = "#8be9fd";
            error = "#ff5555";
            warning = "#ffb86c";
            success = "#50fa7b";
            info = "#8be9fd";
            text = "#f8f8f2";
            textMuted = "#6272a4";
            selectedListItemText = "#f8f8f2";
            background = "#282a36";
            backgroundPanel = "#21222c";
            backgroundElement = "#343746";
            border = "#44475a";
            borderActive = "#6272a4";
            borderSubtle = "#343746";

            diffAdded = "#50fa7b";
            diffRemoved = "#ff5555";
            diffContext = "#6272a4";
            diffHunkHeader = "#6272a4";
            diffHighlightAdded = "#50fa7b";
            diffHighlightRemoved = "#ff5555";
            diffAddedBg = "#1c3327";
            diffRemovedBg = "#3d1e28";
            diffContextBg = "#282a36";
            diffLineNumber = "#6272a4";
            diffAddedLineNumberBg = "#1c3327";
            diffRemovedLineNumberBg = "#3d1e28";

            markdownText = "#f8f8f2";
            markdownHeading = "#bd93f9";
            markdownLink = "#8be9fd";
            markdownLinkText = "#8be9fd";
            markdownCode = "#50fa7b";
            markdownBlockQuote = "#6272a4";
            markdownEmph = "#f1fa8c";
            markdownStrong = "#ffb86c";
            markdownHorizontalRule = "#44475a";
            markdownListItem = "#8be9fd";
            markdownListEnumeration = "#8be9fd";
            markdownImage = "#ff79c6";
            markdownImageText = "#ff79c6";
            markdownCodeBlock = "#282a36";

            syntaxComment = "#6272a4";
            syntaxKeyword = "#ff79c6";
            syntaxFunction = "#50fa7b";
            syntaxVariable = "#f8f8f2";
            syntaxString = "#f1fa8c";
            syntaxNumber = "#bd93f9";
            syntaxType = "#8be9fd";
            syntaxOperator = "#ff79c6";
            syntaxPunctuation = "#f8f8f2";
          };
        };
      };
    };
}
