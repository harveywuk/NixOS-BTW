{ den, inputs, ... }:
{
  den.aspects.kernel.nixos =
    { pkgs, config, ... }:
    {
      imports = [ inputs.chaotic.nixosModules.default ];

      boot.kernelPackages = pkgs.linuxPackages_cachyos-lto-znver4;

      boot.blacklistedKernelModules = [ "hid_logitech_hidpp" ];

      # Exposes DDC/CI monitors as /sys/class/backlight devices, so brightness
      # can be controlled the same way as a laptop panel instead of via
      # userspace ddcutil (which fails DDC/CI writes on some monitors, e.g.
      # the AW3423DWF, when noctalia's fast sleep-multiplier is used).
      boot.extraModulePackages = [ config.boot.kernelPackages.ddcci-driver ];
      boot.kernelModules = [
        "ddcci"
        "ddcci_backlight"
      ];

      # ddcci's autoprobing is broken on kernel 6.8+ (upstream i2c core
      # dropped i2c_new_scanned_device), so bind it manually to every DDC/CI
      # monitor ddcutil finds. This is what actually makes ddcci-backlight
      # create the /sys/class/backlight devices above.
      systemd.services.ddcci-bind = {
        description = "Bind ddcci driver to detected DDC/CI monitors";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-udev-settle.service" ];
        wants = [ "systemd-udev-settle.service" ];
        path = [
          pkgs.ddcutil
          pkgs.gawk
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          for bus in $(ddcutil detect --brief | awk -F'i2c-' '/I2C bus/ {print $2}'); do
            echo "ddcci 0x37" > "/sys/bus/i2c/devices/i2c-$bus/new_device" 2>/dev/null || true
          done
        '';
      };

      # Suppress kernel messages on console/TTY
      boot.kernelParams = [
        "quiet"
        "loglevel=3"
        "systemd.show_status=auto"
        "rd.udev.log_level=3"
        # Allow GPU soft-reset on ring timeout instead of full hang
        "amdgpu.gpu_recovery=1"
      ];
    };
}
