{ den, inputs, ... }:
{
  den.aspects.kernel.nixos =
    {
      pkgs,
      config,
      cachyosKernelPkgs,
      ...
    }:
    {
      imports = [ inputs.chaotic.nixosModules.default ];

      # From nix-cachyos-kernel (cachyosKernelPkgs), not chaoticPkgs. Taken
      # from its own flake outputs (already built against its
      # own nixpkgs pin, cache-compatible with its Attic cache) rather than
      # routed through pkgs.* - same reasoning as chaotic below, see
      # modules/nix/cachyos-kernel-pkgs.nix.
      #
      # hardware.nvidia.package in hosts/mrpickles/default.nix is taken from
      # this same set for exactly that reason - see the vermagic note there.
      # It must be switched in lockstep with the variant below.
      #
      # This means the kernel is built against a nixpkgs pin different from
      # both ours and chaotic's. That is fine for a kernel, but any
      # out-of-tree module must come from this same package set - see
      # boot.extraModulePackages below, which uses config.boot.kernelPackages
      # for exactly that reason.
      #
      # NOTE: an INTEL_TDX_HOST override used to live here to silence a
      # "not supported by this platform" boot message on AMD. It patched
      # the inner `configfile` derivation, which re-hashed the kernel and
      # so guaranteed a from-source build. Dropped deliberately: the
      # message is cosmetic, the rebuild was not. Do not reintroduce it
      # without accepting that cost.

      # EEVDF, not BORE. Switched away from linuxPackages-cachyos-bore-lto-zen4
      # on 2026-08-20: BORE was suspected of causing desktop hitches. This
      # variant sets no `cpusched` at all in the flake's kernel-cachyos/
      # default.nix (the bore one explicitly sets cpusched = "bore"), so it is
      # the stock EEVDF scheduler. Same 7.1.8, same `lto = "thin"`, same zen4
      # march - the scheduler is the only deliberate difference.
      #
      # If the hitches persist, the scheduler was not the cause and this should
      # go back rather than being left as cargo cult.
      boot.kernelPackages = cachyosKernelPkgs."linuxPackages-cachyos-latest-lto-zen4";

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
        # Disable Spectre/Meltdown-class speculative-execution mitigations
        # for CPU performance. Trades protection against side-channel
        # attacks (an attacker running arbitrary code on this box, e.g. a
        # malicious browser tab or VM guest, could read memory it shouldn't)
        # for throughput - acceptable on a single-user gaming desktop, not
        # something to carry onto a multi-tenant or untrusted-workload box.
        "mitigations=off"
        # Only back explicitly-madvised allocations with huge pages instead
        # of "always" promoting eligible mappings. Avoids khugepaged
        # compaction work landing mid-frame as a stutter; costs a little
        # throughput on workloads that would've benefited from unprompted
        # THP.
        "transparent_hugepage=madvise"
      ];
    };
}
