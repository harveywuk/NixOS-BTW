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
          (final: prev: {
            pulsar-mouse-linux = prev.python3Packages.buildPythonApplication {
              pname = "pulsar-mouse-linux";
              version = "0.1.0";
              pyproject = true;

              src = inputs.pulsar-mouse-linux-src;

              build-system = [ prev.python3Packages.setuptools ];

              dependencies = [
                prev.python3Packages.pyusb
                prev.python3Packages.pygobject3
              ];

              nativeBuildInputs = [
                prev.wrapGAppsHook4
                prev.gobject-introspection
              ];

              buildInputs = [
                prev.gtk4
                prev.libadwaita
                prev.libdbusmenu
              ];

              # udev rules aren't picked up automatically from a Python build;
              # ship them under lib/udev/rules.d so services.udev.packages finds them.
              postInstall = ''
                install -Dm444 udev/50-pulsar-mouse.rules $out/lib/udev/rules.d/50-pulsar-mouse-linux.rules
                install -Dm444 data/pulsar-mouse.desktop $out/share/applications/pulsar-mouse.desktop
                install -Dm444 data/pulsar-mouse.svg $out/share/icons/hicolor/scalable/apps/pulsar-mouse.svg
              '';

              meta = {
                description = "Linux configuration tool for Pulsar gaming mice (X2A, X2H, Xlite)";
                homepage = "https://github.com/packerlschupfer/pulsar-mouse-linux";
                license = final.lib.licenses.mit;
                mainProgram = "pulsar-mouse-gui";
                platforms = final.lib.platforms.linux;
              };
            };
          })
        ];
      };
    };
}
