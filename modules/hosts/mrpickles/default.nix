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
      den.aspects.nixsettings

      # Hardware
      den.aspects.bluetooth
      den.aspects.coolercontrol
      den.aspects.kernel
      den.aspects.openrgb

      # Network printer stuff, specific to my network
      den.aspects.print
      den.aspects.udev

      # Security
      den.aspects.sops
      den.aspects.pcscd
      # den.aspects.ly
      den.aspects.noctalia-greeter
      den.aspects.polkit

      # Services
      den.aspects.ananicy
      # den.aspects.networkdrives

      # System packages
      den.aspects.systempackages
      den.aspects.zen-browser
    ];

    nixos =
      {
        lib,
        pkgs,
        config,
        ...
      }:
      {
        imports = [ (inputs.self + "/hosts/mrpickles/hardware-configuration.nix") ];

        boot = {
          loader.limine = {
            enable = true;
            secureBoot.enable = false;
            style.interface.resolution = lib.mkDefault "3440x1440";
            extraEntries = ''
              /Windows
                  protocol: efi
                  path: boot():/efi/Microsoft/Boot/bootmgfw.efi
            '';
          };
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
          ];
          blacklistedKernelModules = [
            #"mt7925e"
            #"snd_hda_intel"
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
            powerManagement.enable = false;
            open = true; # Ampere+ supports the open kernel module
            package = pkgs.nvidia_cachyos;
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
          StanardOutput = "journal";
          StandardError = "journal";
        };

        powerManagement.cpuFreqGovernor = "performance";

        environment.variables = {
          #AMD_VULKAN_ICD = "RADV";
          #MESA_SHADER_CACHE_MAX_SIZE = "32G";
          LIBVA_DRIVER_NAME = "nvidia";
          GBM_BACKEND = "nvidia-drm";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          WLR_NO_HARDWARE_CURSORS = "1";
        };

        environment.systemPackages = with pkgs; [
          #sbctl
          #amdgpu_top
          #blender-rocm
        ];
      };
  };
}
