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
      den.aspects.kernel

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
      # den.aspects.ananicy
      # den.aspects.networkdrives

      # System packages
      den.aspects.systempackages
    ];

    nixos =
      {
        lib,
        pkgs,
        config,
        ...
      }:
      {
        imports = [ (inputs.self + "/hosts/void/hardware-configuration.nix") ];

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
            kernelModules = [ "amdgpu" ];
          };
          kernelPackages = pkgs.linuxPackages_zen;
          kernelModules = [
            "ntsync"
          ];
          kernelParams = [
            "splash"
          ];
          blacklistedKernelModules = [
            #"mt7925e"
            #"snd_hda_intel"
          ];
        };

        hardware = {
          firmware = [ pkgs.linux-firmware ];
          graphics = {
            enable = lib.mkDefault true;
            enable32Bit = lib.mkDefault true;
          };
          steam-hardware.enable = true;
        };

        powerManagement.cpuFreqGovernor = "performance";

        environment.variables = {
          #AMD_VULKAN_ICD = "RADV";
          #MESA_SHADER_CACHE_MAX_SIZE = "32G";
        };

        environment.systemPackages = with pkgs; [
          #sbctl
          #amdgpu_top
          #blender-rocm
        ];
      };
  };
}
