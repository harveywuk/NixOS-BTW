{ den, inputs, ... }:
{
  den.aspects.overlays.nixos =
    { ... }:
    {
      nixpkgs = {
        overlays = [
          inputs.chaotic.overlays.default
          (final: prev: {
            blender-rocm = prev.symlinkJoin {
              name = "blender-rocm";
              paths = [ prev.pkgsRocm.blender ];

              nativeBuildInputs = [ prev.makeWrapper ];

              postBuild = ''
                wrapProgram $out/bin/blender --set LD_PRELOAD "${prev.rocmPackages.rocm-comgr}/lib/libamd_comgr.so.3"
              '';
            };
          })
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
        ];
      };
    };
}
