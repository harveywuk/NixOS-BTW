{ den, inputs, ... }:
{
  den.aspects.nixsettings.nixos =
    {
      lib,
      pkgs,
      ...
    }:
    {
      nixpkgs = {
        config = {
          allowUnfree = true;
          permittedInsecurePackages = [
            "electron-40.10.5" # required by winboat
          ];
        };
      };
      nix = {
        nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
        gc = {
          automatic = lib.mkDefault true;
          dates = lib.mkDefault "daily";
          options = lib.mkDefault "--delete-older-than 5d";
        };
        settings = {
          # Push realised local builds into the personal Cachix cache.
          post-build-hook = pkgs.writeShellScript "push-to-sfdgahf12345-cachix" ''
            set -eu

            if ! command -v cachix >/dev/null 2>&1; then
              exit 0
            fi

            if [ -z "$OUT_PATHS" ]; then
              exit 0
            fi

            if [ -f /run/secrets/cachix ]; then
              export CACHIX_AUTH_TOKEN="$(cat /run/secrets/cachix)"
            else
              exit 0
            fi

            for path in $OUT_PATHS; do
              cachix push sfdgahf12345 "$path"
            done
          '';
          # enable flakes

          experimental-features = [
            "nix-command"
            "flakes"
          ];
          auto-optimise-store = true;
          substituters = [
            "https://cache.nixos.org"
            "https://nix-community.cachix.org"
            "https://cache.garnix.io"
            "https://hyprland.cachix.org"
            "https://neonvoidx.cachix.org"
            "https://noctalia.cachix.org"
          ];
          trusted-substituters = [
            # Official nix cache
            "https://cache.nixos.org"
            # Garnix
            "https://cache.garnix.io"
            # Nix Community Cache
            "https://nix-community.cachix.org"
            # hyprland cache
            "https://hyprland.cachix.org"
            # Personal Cachix cache
            "https://neonvoidx.cachix.org"
            # Noctalia
            "https://noctalia.cachix.org"
          ];
          trusted-public-keys = [
            # Official nix cache
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            # Personal Cachix cache
            "sfdgahf12345.cachix.org-1:GZ4gDiZwHEp8UTJrfFGSnlbSSnha1YQESGXF1QeEBV4="
            # Garnix
            "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
            # Nix community cache
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            # hyprland cache
            "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
            # Noctalia
            "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
          ];
          trusted-users = [
            "root"
            "@wheel"
          ];
          allowed-users = [
            "root"
            "@wheel"
          ];
          connect-timeout = 10;
          stalled-download-timeout = 100;
          download-attempts = 5;
        };
      };

      # Log rebuild
      system.activationScripts.logRebuildTime = {
        text = ''
          LOG_FILE="/var/log/nixos-rebuild-log.json"
          TIMESTAMP=$(date "+%d/%m")
          GENERATION=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]\+')

          echo "{\"last_rebuild\": \"$TIMESTAMP\", \"generation\": $GENERATION}" > "$LOG_FILE"
          chmod 644 "$LOG_FILE"
        '';
      };
    };
}
