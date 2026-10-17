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
{
  baidunetdisk = final.callPackage ../packages/baidunetdisk { };

  # Keep Blender and the system HIP runtime on the same stable package set.
  blender = prev.blender.override {
    rocmSupport = true;
  };

  codex = final.callPackage ../packages/codex { };

  dwproton-bin = final.callPackage ../packages/dwproton-bin {
    base = prev.dwproton-bin;
  };

  fastfetch = final.callPackage ../packages/fastfetch {
    base = prev.fastfetch;
  };

  harmonyos-sans = final.callPackage ../packages/harmonyos-sans { };

  nix-tree = final.callPackage ../packages/nix-tree {
    base = prev.nix-tree;
  };

  unstable = unstablePkgs;
}
