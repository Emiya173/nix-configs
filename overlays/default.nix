{ inputs }:

_final: prev:

let
  unstablePkgs = import inputs.nixpkgs-unstable {
    inherit (prev.stdenv.hostPlatform) system;
    config.allowUnfree = true;
    overlays = [
      (_: unstablePrev: {
        # GUI launchers may not inherit NIXOS_OZONE_WL from the niri session.
        # Native Wayland lets QQ follow each output's fractional scale.
        qq = unstablePrev.qq.override {
          commandLineArgs = prev.lib.escapeShellArgs [
            "--ozone-platform=wayland"
            "--enable-features=WaylandWindowDecorations"
            "--enable-wayland-ime=true"
            "--wayland-text-input-version=3"
          ];
        };
      })
    ];
  };
in
{
  inherit (unstablePkgs)
    codex
    ;

  unstable = unstablePkgs;
}
