{ den, inputs, ... }:
{
  den.aspects.overlays.nixos =
    { ... }:
    {
      nixpkgs = {
        overlays = [
          inputs.chaotic.overlays.default
          (final: prev: {
            bibata-modern-ice-hyprcursor = prev.stdenv.mkDerivation {
              pname = "bibata-modern-ice-hyprcursor";
              version = "unstable";

              src = inputs.bibata-hypr-src;

              nativeBuildInputs = [
                (prev.python3.withPackages (ps: [ ps.clickgen ]))
                prev.librsvg
                prev.xcursorgen
              ];

              # Only build the hyprcursor (vector) format for this one theme,
              # skipping the x11/xcursor build to keep this quick.
              buildPhase = ''
                runHook preBuild
                python3 src/cursor_utils.py --hypr --theme Bibata-Modern-Ice --out-dir ./out
                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall
                mkdir -p $out/share/icons
                cp -r ./out/Bibata-Modern-Ice $out/share/icons/Bibata-Modern-Ice
                runHook postInstall
              '';

              meta = {
                description = "Bibata Modern Ice cursor theme, built in native hyprcursor (vector) format";
                homepage = "https://github.com/rtgiskard/bibata_cursor";
                license = final.lib.licenses.gpl3Only;
                platforms = final.lib.platforms.all;
              };
            };
          })
          # nixpkgs builds FreeRDP with WITH_VAAPI off, following upstream,
          # which marks it "[experimental]" in cmake/ConfigOptions.cmake.
          # Without it every H.264 frame in a WinBoat session is decoded on
          # the CPU by OpenH264/ffmpeg - which is what makes Teams video
          # calls fall over. The flag only gates an ffmpeg hwaccel path in
          # libfreerdp/codec/h264_ffmpeg.c, so no extra buildInputs are
          # needed; ffmpeg already links libva.
          #
          # Decode lands on /dev/dri/renderD128 (the 3090) via the already
          # configured LIBVA_DRIVER_NAME=nvidia + NVD_BACKEND=direct. Set
          # FREERDP_VAAPI_DEVICE=/dev/dri/renderD129 to move it to the
          # Raphael iGPU instead; both report H264 VLD in vainfo.
          (final: prev: {
            freerdp = prev.freerdp.overrideAttrs (old: {
              cmakeFlags = (prev.lib.remove "-DWITH_VAAPI:BOOL=FALSE" old.cmakeFlags) ++ [
                (prev.lib.cmakeBool "WITH_VAAPI" true)
              ];
            });
          })
          # pulsar-mouse-linux now packages itself (flake.nix added
          # 2026-08-08) - this just pulls that in rather than duplicating
          # the derivation here.
          inputs.pulsar-mouse-linux.overlays.default
          # polaris-stream, gamescope-polaris (+ gamescope-hdr alias),
          # xdg-desktop-portal-gamescope. cudaSupport is forced on inside
          # the flake's own nixpkgs instance regardless of ours.
          inputs.polaris.overlays.default
          # llama.cpp with the CUDA backend, under its own attribute name so
          # both the llama-cpp and lemonade aspects can reach the exact same
          # build (lemonade points its llamacpp.cuda_bin at it).
          #
          # Built from an explicit `import inputs.nixpkgs` rather than `prev`
          # on purpose. nix-amd-ai's overlay - added by lemonade.nix via its
          # nixosModules.default - rebinds `llama-cpp` to a derivation from
          # *its own* pinned nixpkgs, whose config carries neither allowUnfree
          # nor our cudaCapabilities. Reading `prev.llama-cpp` would therefore
          # give a different answer depending on which overlay the module
          # system happens to order first: either an unfree-CUDA eval failure
          # or a silent build for every capability. A fresh instance is
          # order-independent, and the attribute name is ours alone so nothing
          # downstream can shadow it.
          (final: prev: {
            llama-cpp-cuda =
              (import inputs.nixpkgs {
                inherit (prev.stdenv.hostPlatform) system;
                config = {
                  allowUnfree = true;
                  # The 3090 is GA102 - compute capability 8.6, and the only
                  # CUDA device in the box. nixpkgs otherwise builds every
                  # capability the toolkit supports, multiplying an already
                  # uncached compile by a dozen architectures we can't run.
                  cudaCapabilities = [ "8.6" ];
                };
              }).llama-cpp.override
                { cudaSupport = true; };
          })
        ];
      };
    };
}
