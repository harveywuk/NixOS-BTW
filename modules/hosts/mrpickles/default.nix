{ den, inputs, ... }:
{
  den.aspects.mrpickles = {
    includes = [
      # Core system
      den.aspects.boot
      den.aspects.locale
      den.aspects.networking
      den.aspects.systemd
      den.aspects.users
      den.aspects.overlays
      den.aspects.chaotic-pkgs
      den.aspects.cachyos-kernel-pkgs
      den.aspects.nixsettings

      # Hardware
      den.aspects.bluetooth
      den.aspects.coolercontrol
      den.aspects.kernel
      den.aspects.openrgb

      den.aspects.udev

      # Security
      den.aspects.sops
      den.aspects.pcscd
      den.aspects.noctalia-greeter
      den.aspects.polkit

      # Services
      den.aspects.bpftune
      den.aspects.zram
      # den.aspects.networkdrives

      # Local AI
      den.aspects.hermes-webui
      den.aspects.llama-cpp
      den.aspects.lemonade
      den.aspects.docker-gpu-serving

      # System packages
      den.aspects.systempackages
      den.aspects.zen-browser
    ];

    nixos =
      {
        lib,
        pkgs,
        config,
        cachyosKernelPkgs,
        ...
      }:
      let
        nvidiaBase = cachyosKernelPkgs."linuxPackages-cachyos-latest-lto-zen4".nvidiaPackages.new_feature;

        # 7.1.8 removed <linux/of_gpio.h>, so nvidia's conftest stops defining
        # NV_LINUX_OF_GPIO_H_PRESENT and the of_get_named_gpio() compat shim in
        # kernel-open/common/inc/nv-linux.h compiles for the first time. Its
        # __to_hwgpio() helper takes a `const struct gpio_device *` but hands it
        # to gpio_device_get_chip(), which takes a non-const one - so with this
        # kernel's CONFIG_OF_GPIO=y every translation unit that includes
        # nv-linux.h dies on -Werror=incompatible-pointer-types-discards-
        # qualifiers. The shim's only caller already holds a non-const gdev
        # (from gpio_device_find_by_fwnode), so dropping const is a no-op for
        # callers and just restores the signature the kernel API expects.
        #
        # Overriding via `//` rather than overrideAttrs+passthru because the
        # NixOS module reaches the kernel module as `nvidia_x11.open`
        # (nixos/modules/hardware/video/nvidia.nix), a passthru attr that
        # overrideAttrs on the parent would not touch.
        #
        # Drop this once the nix-cachyos-kernel input carries a 610.x that
        # builds against 7.1.8 unpatched; --replace-fail makes it fail loudly.
        nvidiaPackage = nvidiaBase // {
          open = nvidiaBase.open.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace kernel-open/common/inc/nv-linux.h \
                --replace-fail \
                  'static inline int __to_hwgpio(const struct gpio_device *gdev,' \
                  'static inline int __to_hwgpio(struct gpio_device *gdev,'
            '';
          });
        };
      in
      {
        imports = [ (inputs.self + "/hosts/mrpickles/hardware-configuration.nix") ];

        fileSystems."/mnt/games" = {
          device = "/dev/disk/by-uuid/a657733b-d5d0-47d7-815f-1c57b13b1f96";
          fsType = "xfs";
          options = [
            "defaults"
            "nofail"
          ];
        };

        fileSystems."/mnt/storage" = {
          device = "/dev/disk/by-uuid/ddd50e18-2d1a-42a9-a576-a6190103a431";
          fsType = "xfs";
          options = [
            "defaults"
            "nofail"
          ];
        };

        boot = {
          initrd = {
            enable = true;
            kernelModules = [
              "amdgpu"
              "nvidia"
              "nvidia_modeset"
              "nvidia_drm"
            ];
          };
          kernelModules = [
            "ntsync"
            # The N7 B650E's onboard fan headers are wired to an NCT6796D-S/
            # NCT6799D-R Super I/O chip. It's an ISA-bus device, so unlike
            # PCI/USB hwmon drivers it never autoloads via udev - without
            # this it just silently never shows up, and only the GPU's own
            # fans (amdgpu/nvidia hwmon) are visible to CoolerControl.
            "nct6775"
          ];
          kernelParams = [
            "splash"
            "nvidia-drm.modeset=1"
            "nvidia_drm.fbdev=1"
          ];
        };

        hardware = {
          i2c.enable = true;
          firmware = [ pkgs.linux-firmware ];
          graphics = {
            enable = lib.mkDefault true;
            enable32Bit = lib.mkDefault true;
          };
          steam-hardware.enable = true;

          # NVIDIA RTX 3090
          nvidia = {
            modesetting.enable = true;
            # Preserve VRAM across suspend (NVreg_PreserveVideoMemoryAllocations=1
            # plus the nvidia-suspend/resume/hibernate units). Was false, which
            # meant the GPU came back from every suspend with invalid state:
            # NVRM Xid 13 (Graphics Exception) within a second of "PM: suspend
            # exit", then Hyprland aborting ~10s later on
            # glGetGraphicsResetStatus == GL_GUILTY_CONTEXT_RESET, which it
            # refuses to survive. Crashed on 8 consecutive resumes before this.
            # Costs a slower suspend/resume - 24GB of VRAM gets staged out.
            powerManagement.enable = true;
            open = true; # Ampere+ supports the open kernel module
            # From cachyosKernelPkgs, matched to boot.kernelPackages in
            # kernel.nix, NOT chaoticPkgs.nvidia_cachyos. Out-of-tree module
            # loading is gated on vermagic (the exact kernel release
            # string), and chaotic's cachyos kernels all report the same
            # "7.1.8-cachyos" regardless of flavor while this flake's
            # report "7.1.8-cachyos-lto" - nvidia_cachyos would fail to
            # load against this kernel with a version magic mismatch.
            #
            # new_feature (610.x, NVIDIA's "New Feature Branch") rather than
            # stable (595.x) - deliberate choice to track 610, not a stray
            # leftover. Comes from this same cachyosKernelPkgs set, so it's
            # still vermagic-matched to boot.kernelPackages above (unlike the
            # chaoticPkgs.nvidia_cachyos pairing warned about in kernel.nix,
            # which is a different, unverified source for the same version).
            package = nvidiaPackage;
          };
        };

        services.xserver.videoDrivers = [ "nvidia" ];

        services.seatd.enable = true;

        systemd.services.greetd.environment = {
          # <-- add this block
          NOCTALIA_GREETER_LOG = "stderr";
          WLR_LOG = "info";
        };
        systemd.services.greetd.serviceConfig = {
          StandardOutput = "journal";
          StandardError = "journal";
        };

        powerManagement.cpuFreqGovernor = "performance";

        environment.variables = {
          LIBVA_DRIVER_NAME = "nvidia";
          NVD_BACKEND = "direct";
          GBM_BACKEND = "nvidia-drm";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        };
      };
  };
}
