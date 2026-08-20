# Generic host prerequisites for Dockerized GPU LLM serving on this box - the
# nvidia-container-toolkit wiring and HF download tooling that any such setup
# needs, NixOS-specific because none of it ships by default. Originally
# written for noonghunna/club-3090 (community docker-compose recipes for
# vLLM/llama.cpp/ik_llama on RTX 3090-class cards, driven imperatively via its
# own scripts/*.sh); qwen38-27b-rtx3090 (~/qwen38-27b-rtx3090, syv-ai's
# patched-vLLM single-repo deployment) is a second, unrelated consumer of the
# same prereqs, which is why this stayed generic rather than following
# club-3090 out. Docker itself already comes from the winboat aspect; model
# weights for whichever repo is active live under /mnt/games/models or a
# repo-local ./models dir via its own .env - deliberately outside the Nix
# store, which would otherwise pin tens of GB per quant onto / across every
# retained generation.
{ den, ... }:
{
  den.aspects.docker-gpu-serving.nixos =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      hardware.nvidia-container-toolkit.enable = true;

      virtualisation.docker.daemon.settings = {
        # Register the nvidia OCI runtime by hand. On Docker >= 25 the
        # nvidia-container-toolkit module contributes ONLY `features.cdi =
        # true`; its `runtimes.nvidia` block sits behind the deprecated
        # `virtualisation.docker.enableNvidia`, which is off. That leaves CDI
        # as the only way in - devices requested as `nvidia.com/gpu=all`.
        #
        # None of the compose files this aspect serves ask that way - both
        # club-3090's and qwen38-27b-rtx3090's reserve GPUs through the
        # compose-spec form:
        #
        #   deploy.resources.reservations.devices:
        #     - driver: nvidia
        #       capabilities: [gpu]   # or [compute, utility]
        #
        # which resolves through a GPU device driver, i.e. this runtime - not
        # CDI. Without the entry below, `docker compose up` fails with
        # "could not select device driver "nvidia" with capabilities:
        # [[compute utility]]" (or "[[gpu]]").
        runtimes.nvidia.path = "${lib.getOutput "tools" config.hardware.nvidia-container-toolkit.package}/bin/nvidia-container-runtime";

        # Deliberately NOT setting `default-runtime = "nvidia"`. The upstream
        # NixOS block pairs it with the runtime, but docs/CONTAINER_RUNTIMES.md
        # (club-3090's) names its known-good baseline as "Docker Engine 27+
        # with NVIDIA Container Toolkit, no `default-runtime: nvidia` in
        # daemon.json (opt-in via --gpus per-command)", and warns that
        # materially divergent setups surface bugs that aren't pin-fixable.
        # Leaving the default at runc also keeps every unrelated container
        # (winboat) off the nvidia shim.
      };

      environment.systemPackages = [
        # hf_transfer is the multi-threaded download backend `hf download`
        # opts into; without it weight pulls fall back to a single stream.
        # Used for ad-hoc host-side pulls (e.g. GGUF quants shared with
        # lemonade's extra_models_dir) - the qwen38-27b-rtx3090 repo's own
        # `prepare` container does its downloading from inside Docker with
        # its own Python env, not this one.
        (pkgs.python3.withPackages (ps: [ ps.hf-transfer ]))

        # Provides both `hf` and `huggingface-cli` on PATH for the same
        # ad-hoc host-side use.
        pkgs.python3Packages.huggingface-hub
      ];
    };
}
