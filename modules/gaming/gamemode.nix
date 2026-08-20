# Feral GameMode: on demand while a game runs (via `gamemoderun %command%` in
# Steam launch options), bumps process nice/ioprio and pins the NVIDIA GPU to
# its max performance level. Doesn't touch CPU scheduling policy, so it's
# orthogonal to the scheduler in modules/hardware/kernel.nix - that governs how
# the CPU scheduler shares time between tasks, GameMode governs process
# priority/GPU clocks, and they don't fight over the same knob. The CPU
# governor is already pinned to "performance" system-wide, so GameMode's
# governor switch is a no-op here; the GPU performance-level pin is the part
# that still matters.
#
# Chosen over an unconditional NVreg_RegistryDwords PowerMizer pin
# (boot.extraModprobeConfig) specifically because it's on-demand - the GPU
# clocks back down to adaptive at idle instead of sitting at P0 (max power
# draw/heat/fan noise) all the time.
#
# It also now reclaims the GPU from the local model servers - see the custom
# hook below.
{ den, ... }:
{
  den.aspects.gamemode.nixos =
    { pkgs, ... }:
    let
      gpuRelease = pkgs.writeShellApplication {
        name = "gamemode-gpu-release";
        runtimeInputs = [
          pkgs.curl
          pkgs.gnugrep
          pkgs.coreutils
          pkgs.systemd
        ];
        text = builtins.readFile ../../assets/scripts/gamemode-gpu-release.sh;
      };
    in
    {
      programs.gamemode.enable = true;

      # ── Reclaiming VRAM for a game ──────────────────────────────────────
      # The local model stack routinely holds ~21 GiB of a 24 GiB card
      # (gemma-4-e4b pinned + a heavy model in the rotating slot), which is
      # most of what a game wants. GameMode already knows exactly when a game
      # starts, so it is the natural place to hand the card over.
      #
      # This replaced an attempt to use lemonade's OWN eviction engine, which
      # looked like the obvious answer and is not. lemond has undocumented
      # `auto_evict` / `auto_evict_threshold_pct` keys (absent from
      # defaults.json, but settable over /internal/set, and the VRAM monitor
      # does work on NVIDIA - it shells out to `nvidia-smi --query-gpu=
      # memory.used,memory.total`). They were tested here on 2026-08-20 and
      # the mechanism is unusable on this box, for a structural reason:
      #
      #   two models resident is ALREADY ~94% of the card
      #
      # so there is no headroom band between "normal" and "under pressure".
      # Any threshold low enough to fire before a game OOMs is also low enough
      # to fire on the steady state - observed directly, with
      # auto_evict_threshold_pct = 0.85 the rotating model was evicted DURING
      # ITS OWN LOAD:
      #   (on_vram_pressure) VRAM pressure critical (93.97% >= 85.00%).
      #   (evaluate_servers) Eviction Engine unloading model:
      #                      extra.muse-glimmer-30b due to score/pressure/idle.
      # and any threshold above 94% never fires until the game has already
      # failed to allocate. Eviction is also reactive and takes ~2s, which a
      # game allocating in a burst will not wait for. `auto_evict` is therefore
      # pinned OFF in modules/ai/lemonade.nix rather than left at its default.
      #
      # A GameMode hook has none of those problems: it is proactive, it runs
      # before the game allocates anything, and it is not guessing.
      #
      # No `end` hook on purpose. lemond auto-loads a model on the next request
      # ("Auto-loading model: gemma-4-e4b"), so the coordinator comes back by
      # itself; reloading it here would instead grab ~4.9 GiB the moment a game
      # exits, while the user is likely still in a launcher. llama-server-qwen38
      # deliberately stays down - it never autostarts (see ai/llama-cpp.nix).
      programs.gamemode.settings.custom.start = "${gpuRelease}/bin/gamemode-gpu-release";
    };
}
