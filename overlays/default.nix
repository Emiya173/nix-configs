{ inputs }:

final: prev:

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
(import ../nur/overlay.nix final prev)
// {
  # Keep Blender and the system HIP runtime on the same stable package set.
  blender = prev.blender.override {
    rocmSupport = true;
  };

  # NTFS3 mounts need no NTFS-3G tools; both packages only add them to PATH.
  os-prober = prev.os-prober.override { ntfs3g = null; };
  udisks = prev.udisks.override { ntfs3g = null; };

  unstable = unstablePkgs;
}
