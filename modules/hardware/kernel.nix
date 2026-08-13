{ den, inputs, ... }:
{
  den.aspects.kernel.nixos =
    { pkgs, config, chaoticPkgs, ... }:
    {
      imports = [ inputs.chaotic.nixosModules.default ];

      # Taken from chaoticPkgs, NOT from pkgs.* (which would route through
      # chaotic's overlay and rebuild against our nixpkgs). Combined with
      # chaotic not following nixpkgs in flake-inputs.nix, this is what
      # makes the kernel a cache hit from nyx-cache.chaotic.cx instead of
      # a ~1h local LTO build. See modules/nix/chaotic-pkgs.nix.
      #
      # This means the kernel is built against chaotic's nixpkgs pin while
      # the rest of the system uses ours. That is fine for a kernel, but
      # any out-of-tree module must come from this same package set - see
      # boot.extraModulePackages below, which uses config.boot.kernelPackages
      # for exactly that reason.
      #
      # NOTE: an INTEL_TDX_HOST override used to live here to silence a
      # "not supported by this platform" boot message on AMD. It patched
      # the inner `configfile` derivation, which re-hashed the kernel and
      # so guaranteed a from-source build. Dropped deliberately: the
      # message is cosmetic, the rebuild was not. Do not reintroduce it
      # without accepting that cost.
      boot.kernelPackages = chaoticPkgs.linuxPackages_cachyos-lto-znver4;

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

      # Suppress kernel messages on console/TTY.
      #
      # boot.consoleLogLevel must be set here rather than just passing
      # "loglevel=0" in kernelParams: NixOS's own boot module derives its
      # own "loglevel=${consoleLogLevel}" (default 4) and appends it to
      # kernelParams *after* ours, and the kernel's loglevel= early_param
      # takes whichever occurrence is last on the cmdline — so an explicit
      # "loglevel=0" here was silently overridden back to 4.
      boot.consoleLogLevel = 0;
      boot.kernelParams = [
        "quiet"
        "systemd.show_status=false"
        "rd.udev.log_level=3"
        "rd.systemd.show_status=false"
        # Allow GPU soft-reset on ring timeout instead of full hang
        "amdgpu.gpu_recovery=1"
      ];
    };
}
