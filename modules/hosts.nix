{ den, ... }:
let
  mrpickles = {
    gitName = "harveywuk";
    gitEmail = "accounts@harveyweaver.uk";
    emailName = "hw";
    emailAddress = "harvey.weaver@accounts.uk";
  };
  timezone = "Europe/London";
in
{
  den.hosts.x86_64-linux = {
    nixos-btw = {
      users.mrpickles = mrpickles;

      monitors = {
        main = {
          name = "DP-4";
          mode = "3440x1440@165";
          scale = 1.0;
          bitdepth = 10;
          cm = "dcip3";
          supports_hdr = true;
          supports_wide_color = true;
          vrr = 2;
          sdrbrightness = 0.5;
          sdrsaturation = 1.0;
          sdr_max_luminance = 408;
          sdr_min_luminance = 0.2339;
          position = "0x0";
          primary = true;
        };
        secondary = {
          name = "DP-5";
          mode = "2560x1440@165";
          scale = 1.0;
          bitdepth = 10;
          cm = "dcip3";
          supports_hdr = true;
          supports_wide_color = true;
          vrr = 2;
          sdrbrightness = 0.5;
          sdrsaturation = 1.0;
          sdr_max_luminance = 408;
          sdr_min_luminance = 0.2339;
          position = "350x1440";
          # Transform list:
          # 0 -> normal (no transforms)
          # 1 -> 90 degrees
          # 2 -> 180 degrees
          # 3 -> 270 degrees
          transform = 2;
        };
      };

      isMultiMonitor = true;
      xRes = "3440";
      yRes = "1440";

      greeting = "NixBTW";
      timezone = timezone;
      isGaming = true;
    };
  };
}
