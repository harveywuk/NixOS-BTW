{ den, ... }:
{
  den.aspects.fastfetch = {
    nixos =
      { ... }:
      {
        # Stamps the true install date once, on first boot, to a file that
        # persists forever regardless of how many generations get pruned
        # later (nix-collect-garbage, nh clean, etc. never touch this).
        systemd.services.record-install-date = {
          description = "Record the original NixOS install date (once)";
          wantedBy = [ "multi-user.target" ];
          unitConfig.ConditionPathExists = "!/var/lib/nixos-install-date";
          serviceConfig.Type = "oneshot";
          script = ''
            date +%s > /var/lib/nixos-install-date
          '';
        };
      };

    homeManager =
      { pkgs, config, ... }:
      let
        esc = builtins.fromJSON ''"\u001b"'';
      in
      {
        programs.fastfetch = {
          enable = true;
          settings = {
            "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json";
            display = {
              key.width = 10;
              separator = "";
            };
            logo = {
              type = "kitty-direct";
              # NOTE: Change this if you want a different fastfetch image
              source = "~/nix/assets/nixos-logo.png";
              width = 25;
              padding = {
                top = 1;
                right = 10;
              };
            };
            modules = [
              "break"
              {
                type = "command";
                key = "󰀄 USER";
                keyColor = "#a48cf2";
                text = "whoami";
              }
              {
                type = "os";
                key = "󰣇 OS";
                keyColor = "#04d1f9";
                format = "{name} {version-id}";
              }
              {
                type = "command";
                key = "󰇄 HOST";
                keyColor = "#a48cf2";
                text = "hostname";
              }
              {
                type = "command";
                key = "󰃭 AGE";
                keyColor = "#59d1c6";
                text = "echo $(( ( $(date +%s) - $(cat /var/lib/nixos-install-date 2>/dev/null || date +%s) ) / 86400 )) days";
              }
              {
                type = "command";
                key = "󰌽 KER";
                keyColor = "#37f499";
                text = "echo $(uname -r) $(uname -m)";
              }
              {
                type = "packages";
                key = "󰏗 PKG";
                keyColor = "#f1fc79";
                format = "{all}";
              }
              {
                type = "cpu";
                key = "󰻠 CPU";
                keyColor = "#fbbf24";
                format = "{name}";
              }
              {
                type = "gpu";
                key = "󰍹 GPU";
                keyColor = "#d946ef";
                detectionMethod = "vulkan";
                hideType = "integrated";
                format = "{name}";
              }
              {
                type = "terminal";
                key = "󰆍 TERM";
                keyColor = "#f7c67f";
                format = "{pretty-name}";
              }
              {
                type = "shell";
                key = "󰞷 SH";
                keyColor = "#f265b5";
                format = "{pretty-name}";
              }
              {
                type = "wm";
                key = "󰖲 WM";
                keyColor = "#59d1c6";
                format = "{pretty-name} {version}";
              }
              {
                type = "localip";
                key = "󰩠 IP";
                keyColor = "#2dd4bf";
                format = "{ipv4}";
              }
              {
                type = "uptime";
                key = "󰥔 UP";
                keyColor = "#7081d0";
              }
              {
                type = "memory";
                key = "󰍛 RAM";
                keyColor = "#f16c75";
                format = "{used} / {total} ({percentage})";
              }
              {
                type = "disk";
                folders = "/";
                key = "󰋊 SSD";
                keyColor = "#ebfafa";
                format = "{size-used} / {size-total} ({size-percentage})";
              }
              "break"
              {
                type = "custom";
                format = "${esc}[44m  ${esc}[46m  ${esc}[42m  ${esc}[43m  ${esc}[41m  ${esc}[45m  ${esc}[105m  ${esc}[101m  ${esc}[103m  ${esc}[102m  ${esc}[106m  ${esc}[104m  ${esc}[0m";
              }
              "break"
            ];
          };
        };
      };
  };
}
