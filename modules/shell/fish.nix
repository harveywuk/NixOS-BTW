{ den, ... }:
{
  den.aspects.fish = {
    nixos =
      { pkgs, ... }:
      {
        # Registers fish in /etc/shells, required before it can be set
        # as a user's login shell below.
        programs.fish.enable = true;
        environment.pathsToLink = [ "/share/fish" ];
      };

    homeManager =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        c = config.lib.stylix.colors;
      in
      {
        programs.fish = {
          enable = true;

          # fzf-tab equivalent — fuzzy tab completion menu
          plugins = [
            {
              name = "fzf-fish";
              src = pkgs.fishPlugins.fzf-fish.src;
            }
          ];

          shellAliases = {
            dev = "cd ~/dev";
            findhere = "find . -name";
            e = "nvim";
          };

          functions = {
            findsyms = ''
              set -l search_path $argv[1]
              if test -z "$search_path"
                set search_path "."
              end
              find $search_path -type l -ls
            '';

            deleteall = ''
              find . -name "$argv[1]" -exec rm -rf {} \;
            '';

            y = ''
              set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
              yazi $argv --cwd-file="$tmp"
              if set -l cwd (cat -- "$tmp"); and test -n "$cwd"; and test "$cwd" != "$PWD"
                cd -- "$cwd"
              end
              rm -f -- "$tmp"
            '';

            reload-ssh = ''
              ssh-add -e /usr/local/lib/opensc-pkcs11.so >>/dev/null
              if test $status -gt 0
                echo "Failed to remove previous card"
              end
              ssh-add -s /usr/local/lib/opensc-pkcs11.so
            '';

            timefish = ''
              set -l sh $argv[1]
              if test -z "$sh"
                set sh $SHELL
              end
              for i in (seq 1 10)
                /usr/bin/time $sh -i -c exit
              end
            '';

            ffmpeg-downsize = ''
              if not command -v ffmpeg &>/dev/null
                echo "ffmpeg not found. Please install ffmpeg."
                return 1
              end
              if test (count $argv) -eq 0
                echo "Usage: movconvert <inputfile.mov>"
                return 1
              end
              set -l output (string replace -r '\.[^.]*$' "" -- $argv[1])
              ffmpeg -i $argv[1] -c:v libx264 -c:a copy -crf 20 "$output-small.mov"
            '';

            ffmpeg-togif = ''
              if not command -v ffmpeg &>/dev/null
                echo "ffmpeg not found. Please install ffmpeg."
                return 1
              end
              if test (count $argv) -ne 3
                echo "Usage: togif <input.mp4> <start_time> <duration>"
                echo "Example: togif movie.mp4 6 8.8"
                return 1
              end
              set -l input $argv[1]
              set -l start $argv[2]
              set -l duration $argv[3]
              set -l base (string replace -r '\.mp4$' "" -- $input)
              ffmpeg -ss $start -t $duration -i $input -vf "fps=30,scale=400:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 "$base.gif"
            '';

            skill = ''
              set -l selected (ps aux | awk 'NR>1 {printf "%-8s  %-s\n", $2, $11}' | fzf --prompt="☠ Kill: " --header="PID       NAME")
              if test -n "$selected"
                set -l pid (echo $selected | awk '{print $1}')
                kill -9 $pid; and echo "Killed PID $pid"
              end
            '';
          }
          // lib.optionalAttrs (config.programs.kitty.enable or false) {
            kk = ''
              kitten @ send-text --match-tab state:focused $argv[1] && kitten @ send-key --match-tab state:focused Enter
            '';
          };

          interactiveShellInit = ''
            # Vi-mode (equivalent of zsh-vi-mode)
            set -g fish_greeting
            fish_vi_key_bindings

            # Show system info on every new interactive shell
            if status is-interactive
              fastfetch
            end

            # Colored man pages via bat, since fast-syntax-highlighting's
            # colored-man-pages plugin has no fish port
            set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"

            set -gx ZSH_TAB_TITLE_ONLY_FOLDER "true"
            set -gx FZF_PREVIEW_ADVANCED "bat"
            set -gx FZF_DEFAULT_OPTS "--color=fg:#${c.base05},bg:#${c.base00},hl:#${c.base0B} --color=fg+:#${c.base05},bg+:#${c.base01},hl+:#${c.base0B} --color=info:#${c.base0A},prompt:#${c.base0C},pointer:#${c.base0D} --color=marker:#${c.base0D},spinner:#${c.base0A},header:#${c.base03} --height 80% --layout reverse --border"
            set -gx FZF_PATH "$HOME/.config/fzf"
            set -gx _ZO_EXCLUDE_DIRS "/Applications/**:**/node_modules"
            set -gx _ZO_RESOLVE_SYMLINKS "0"
            set -gx FZF_CTRL_T_COMMAND ""
            set -gx FNM_DIR "$HOME/.cache/fnm"
            set -gx PYENV_ROOT "$HOME/.pyenv"
            set -gx ZVM_SYSTEM_CLIPBOARD_ENABLED "true"
            set -gx XDG_CONFIG_HOME "$HOME/.config"
            set -gx NODE_OPTIONS "--max-old-space-size=8192"
            set -gx CMAKE_PREFIX_PATH "/usr/local:$CMAKE_PREFIX_PATH"
            set -gx LD_LIBRARY_PATH "/usr/local/lib:$LD_LIBRARY_PATH"
            set -gx EDITOR ${if config.programs.neovim.enable or false then "nvim" else "vi"}
            set -gx VISUAL ${if config.programs.neovim.enable or false then "nvim" else "vi"}

            if command -v cmake &>/dev/null; and command -v ninja &>/dev/null
              alias cmakeninja='cmake -S . -B build -G Ninja'
            end

            if test -f ~/.ssh/scm-script.sh
              alias scm-ssh='bash ~/.ssh/scm-script.sh'
              scm-ssh start_agent >/dev/null 2>&1
            end

            if test -d $PYENV_ROOT/bin
              fish_add_path $PYENV_ROOT/bin
            end

            if test -z "$SSH_AUTH_SOCK"
              eval (ssh-agent -c) >/dev/null
            end
            ssh-add -l &>/dev/null; or ssh-add ~/.ssh/id_ed25519 2>/dev/null

            devenv hook fish | source
          '';
        };
      };
  };
}
