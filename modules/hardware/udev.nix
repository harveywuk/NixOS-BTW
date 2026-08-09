{ den, ... }:
{
  den.aspects.udev =
    { host, ... }:
    {
      nixos =
        { pkgs, lib, ... }:
        {
          services = {
            udev.packages = with pkgs; [
              game-devices-udev-rules
              steam-devices-udev-rules
              arduino # provides udev rules for Arduino boards (ttyUSB/ttyACM access)
              pulsar-mouse-linux
              qmk
              qmk-udev-rules
              qmk_hid
              via
              vial
            ];
            # Blacklist udev rule for this host - was gated on host.hostName == "void",
            # but no host in modules/hosts.nix is ever named that (only "nixos-btw" -
            # "void" is just its cosmetic `greeting` string), so this whole block was
            # always inactive. Fixed 2026-08-09 to match the real host.
            udev.extraRules = lib.mkIf (host.hostName == "nixos-btw") ''
              # Block MediaTek Wireless_Device (0e8d:0717) from binding - causes firmware timeout errors
              # DEVTYPE=="usb_device" prevents matching on interfaces which lack the authorized attr
              SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="0717", ATTR{authorized}="0"
              # Via Keyboards
              KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", OWNER="mrpickles", TAG+="uaccess", TAG+="udev-acl"
              # Keychron Q1 HE (ANSI encoder) - VID/PID from tymon3310/vial-qmk's
              # vial-updated-keychron branch, keyboards/keychron/q1_he/{info,ansi_encoder/keyboard}.json.
              # Redundant with the generic "Via Keyboards" rule above right
              # now (vial:f64c2b3c is Vial's generic magic serial, not
              # device-specific, so that rule alone already matches this
              # keyboard) - kept anyway as explicit documentation of which
              # device is expected here, in case the generic rule is ever
              # narrowed later.
              KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="0b10", MODE="0660", OWNER="mrpickles", TAG+="uaccess", TAG+="udev-acl"
            '';
          };
        };
    };
}
