{ den, ... }:
{
  den.aspects.winboat =
    { ... }:
    {
      nixos =
        { ... }:
        {
          # WinBoat runs its Windows VM inside a Docker container
          virtualisation.docker.enable = true;
        };

      homeManager =
        { pkgs, ... }:
        {
          # H.264 decode runs on the 3090, which is simply what happens by
          # default: WinBoat's xfreerdp child (WITH_VAAPI enabled via
          # modules/nix/overlays.nix) inherits LIBVA_DRIVER_NAME=nvidia and
          # NVD_BACKEND=direct from the session (modules/hosts/mrpickles/
          # default.nix). Nothing here has to ask for it.
          #
          # ── Why this was ever moved off the 3090, and why it is back ──────
          # It used to be pinned to the Raphael iGPU by a wrapper that resolved
          # the amdgpu render node at launch and exported FREERDP_VAAPI_DEVICE
          # at it. That existed for one reason: with den.aspects.lemonade
          # holding two models, the card sat near its limit and WinBoat's
          # window lost its render surface -
          #   [nvidia-drm] Failed to allocate NVKMS video memory for GEM object
          # - so decode was isolated onto the iGPU to escape the contention.
          #
          # That pressure is no longer the RESTING state. As of 2026-08-20 the
          # idle reaper in modules/ai/lemonade.nix unloads the unpinned heavy
          # model 30 minutes after its last use, so day to day the card holds
          # only the ~4.9 GiB pinned coordinator - about 7.1 GiB used of 24576
          # MiB, leaving ~17 GiB. Decode has room on the better GPU again.
          #
          # ── The caveat, stated plainly ───────────────────────────────────
          # That headroom is CONDITIONAL, not permanent. Anything that reaches
          # muse-glimmer-30b - a delegate_task from the coordinator, any turn
          # on one of the bots in modules/ai/hermes-bots.nix - pulls ~16 GiB
          # straight back in and returns the card to ~93% used with ~1.6 GiB
          # free, which is the exact condition the NVKMS allocation failure was
          # first seen under. The reaper then gives it back, but only after the
          # idle timeout.
          #
          # So: driving Hermes hard WHILE WinBoat is running can still
          # reproduce the original symptom. If it does, the options in
          # increasing order of effort are
          #   1. `lemonade-idle-reaper` by hand before launching WinBoat
          #      (LEMONADE_IDLE_SECONDS=120 to be less patient about it), or
          #      call it from a wrapper the way GameMode's custom.start hook
          #      does in modules/gaming/gamemode.nix
          #   2. put FREERDP_VAAPI_DEVICE back, pointing at the amdgpu render
          #      node. Match by BOUND DRIVER NAME, never a fixed
          #      /dev/dri/renderD path: the numbering follows driver probe
          #      order and has been observed swapping between boots on this
          #      machine (amdgpu is renderD128 and nvidia renderD129 as of this
          #      boot, and the overlay comment for WITH_VAAPI still claims the
          #      3090 is renderD128 from an earlier one). Same reasoning as
          #      assets/scripts/polaris-pin-nvidia-adapter.sh.
          home.packages = [ pkgs.winboat ];
        };
    };
}
