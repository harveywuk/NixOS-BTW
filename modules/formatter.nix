# Wires treefmt.toml up as the flake's formatter so `nix fmt` works.
#
# treefmt.toml has configured nixfmt for a while, but nothing exposed a
# `formatter` output, so both `nix fmt` and the `nix run .#fmt` the README
# advertised errored out with "does not provide attribute". treefmt is
# wrapped rather than used bare so it always finds nixfmt on PATH,
# independent of what happens to be in environment.systemPackages.
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.writeShellApplication {
        name = "treefmt-nixfmt";
        runtimeInputs = [
          pkgs.treefmt
          pkgs.nixfmt
        ];
        text = ''exec treefmt "$@"'';
      };
    };
}
