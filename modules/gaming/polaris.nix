# papi-ux/polaris: self-hosted GameStream host (Moonlight/Nova-compatible).
# npm-deps hash for the from-source build was stale on upstream master until
# https://github.com/papi-ux/polaris/pull/392 merged it.
{ den, inputs, ... }:
# Streaming runs on the labwc path (linux_stream_mode = labwc): polaris starts a
# private headless labwc per session and captures it directly over wlr-screencopy.
#
# The other two Linux paths were both tried and dropped:
#
# gamescope_stream always captures the pre-warmed *idle* gamescope, whose size is
# fixed at POLARIS_HDR_WIDTH/HEIGHT - polaris asks PipeWire for the client
# geometry and PipeWire hands back the compositor's real size, so any client with
# a different aspect ratio is letter/pillarboxed. The client-sized "owned spawn"
# branch is unreachable because polaris.service's ExecStartPre refuses to start
# until an idle-role gamescope-0 already exists, so closing that gap needed a
# global_prep_cmd resizing the idle instance per session, plus a PATH shim in
# front of polaris-gamescope-session to stop the nested compositor inheriting the
# same fixed 4K geometry. labwc needs none of it: cage_display_router drives
# `wlr-randr --custom-mode` to the client's resolution when the session starts.
#
# host_virtual_display (a Hyprland headless output via hyprctl) works but this
# build hardwires gamescope in three places - polaris-start force-exports
# POLARIS_PORTAL_DBUS_ADDRESS so ScreenCast can only reach the private gamescope
# portal, the unit pins XDG_CURRENT_DESKTOP=gamescope, and the *generic* portal
# retry in portal_grab.cpp waits for gamescope-0 before retrying. Its portal
# restore token also names the per-session virtual output that polaris destroys on
# teardown, so the token is stale on every reconnect and the host must approve a
# picker each time.
#
# labwc was originally passed over because HDR is structurally impossible there
# (is_hdr() exists only in the portal/KMS backends, which need a real output).
# That is moot: cuda::cuda_t only handles AV_PIX_FMT_NV12, so 10-bit is blocked in
# the encoder converter on *every* path regardless of compositor. labwc's one
# observed failure was the NVENC adapter pointing at the iGPU, which
# polaris-pin-nvidia-adapter below fixes independently of the stream path.
{
  den.aspects.polaris =
    { ... }:
    {
      nixos =
        { ... }:
        {
          # nixpkgs already ships services.polaris for agersant/polaris (an
          # unrelated music server) under the exact same option namespace.
          # Drop it so this flake's services.polaris (GameStream host) options
          # don't collide with it.
          disabledModules = [ "services/misc/polaris.nix" ];
          imports = [ inputs.polaris.nixosModules.polaris ];
          services.polaris = {
            enable = true;
            users = [ "mrpickles" ];
          };
        };

      # Host-level (nixos, above) only installs packages/firewall/permissions.
      # The actual systemd --user unit chain (polaris + portal/idle-gamescope
      # helpers) is defined by the home-manager module.
      homeManager =
        { pkgs, ... }:
        let
          pinNvidiaAdapter = pkgs.writeShellApplication {
            name = "polaris-pin-nvidia-adapter";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gnused
            ];
            text = builtins.readFile ../../assets/scripts/polaris-pin-nvidia-adapter.sh;
          };
        in
        {
          imports = [ inputs.polaris.homeModules.polaris ];
          services.polaris = {
            enable = true;
            # Only seeds ~/.config/polaris/polaris.conf when that file is
            # missing - the web UI owns it afterwards. So this makes a fresh
            # install come up on labwc; an existing host has to be switched in
            # the UI (or by editing the file) as well.
            streamMode = "labwc";

            # Upstream's home-manager module (nix/modules/session-lib.nix)
            # puts both this package and its own writeShellApplication
            # (`sessionBin`) named "polaris-gamescope-session" into
            # home.packages - the CMake install rule for this package ships
            # a same-named copy of the script that nothing actually execs
            # (every systemd unit calls sessionBin's nix-wrapped build via
            # PATH, never this one). Two derivations shipping the same
            # bin/ path make buildEnv refuse the whole home-manager
            # generation, so drop the vestigial copy here rather than
            # patching upstream's module.
            package = pkgs.polaris-stream.overrideAttrs (old: {
              postInstall = (old.postInstall or "") + ''
                rm -f "$out/bin/polaris-gamescope-session"
              '';
            });
          };

          # The idle gamescope + private ScreenCast portal units come up on
          # every stream mode, because polaris.service's ExecStartPre gates
          # unconditionally on gamescope-0 plus a ready portal. On the labwc
          # path they are just a startup precondition - capture itself binds
          # labwc's own socket (use_cage_compositor forces the wlr source in
          # reevaluate_capture_sources), so leave `capture` unset rather than
          # pinning it to portal.

          # renderD* numbering follows driver probe order, so the NVIDIA card and
          # the AMD iGPU can trade places across reboots/kernel updates. When
          # they swap, polaris' adapter_name points NVENC at the iGPU and every
          # session dies at encoder creation ("does not map to a CUDA device")
          # with the client seeing only a timeout. Re-pin it before the daemon
          # reads its config rather than waiting to rediscover this by hand.
          systemd.user.services.polaris-pin-nvidia-adapter = {
            Unit = {
              Description = "Point polaris' NVENC adapter at the nvidia render node";
              Before = [ "polaris.service" ];
            };
            Service = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pinNvidiaAdapter}/bin/polaris-pin-nvidia-adapter";
            };
            Install.WantedBy = [ "polaris.service" ];
          };
        };
    };
}
