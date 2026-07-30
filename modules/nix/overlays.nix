{ den, inputs, ... }:
{
  den.aspects.overlays.nixos =
    { ... }:
    {
      nixpkgs = {
        overlays = [
          inputs.chaotic.overlays.default
          (final: prev: {
            eldritch-icon-theme = prev.stdenv.mkDerivation {
              pname = "eldritch-icon-theme";
              version = "20260529";

              src = final.fetchurl {
                url = "https://github.com/eldritch-theme/icon-theme/releases/download/20260529/Eldritch-Suru-Cthulhu.tar.xz";
                hash = "sha256-HilMQCo3vaZxz1LcCyV5/9SNZ536CkQ9c2c9b14mIbA=";
              };

              dontBuild = true;

              installPhase = ''
                mkdir -p $out/share/icons
                tar -xJf $src -C $out/share/icons
              '';

              meta = {
                description = "Eldritch Suru Cthulhu icon theme";
                homepage = "https://github.com/eldritch-theme/icon-theme";
                license = final.lib.licenses.mit;
                platforms = final.lib.platforms.all;
              };
            };
          })
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
                prev.xorg.xcursorgen
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
