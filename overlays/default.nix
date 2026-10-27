{ inputs }:

final: prev:

let
  inherit (prev.stdenv.hostPlatform) system;
  multiverse = inputs.multiverse.multiverse.${system};
  # Only fetch QQ's recipe from this tree; do not import its package set.
  unstableRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  unstableSource = multiverse.flakeAt unstableRevision;
  # Exact versions avoid parsing the revision history required by fast.at.
  unstableVersions = {
    atuin = "18.23.0";
    dae = "2.1.1";
    hysteria = "2.13.0";
    localsend = "1.18.0";
  };
in
(import ../nur/overlay.nix final prev)
// {
  # QQ is unfree and needs custom flags, so use its upstream recipe with the
  # existing stable dependencies rather than evaluating another package set.
  qq = final.callPackage "${unstableSource}/pkgs/by-name/qq/qq/package.nix" {
    # GUI launchers may not inherit NIXOS_OZONE_WL from the niri session.
    commandLineArgs = prev.lib.escapeShellArgs [
      "--ozone-platform=wayland"
      "--enable-features=WaylandWindowDecorations"
      "--enable-wayland-ime=true"
      "--wayland-text-input-version=3"
    ];
  };

  # Keep Blender and the system HIP runtime on the same stable package set.
  blender = prev.blender.override {
    rocmSupport = true;
  };

  # NTFS3 mounts need no NTFS-3G tools; both packages only add them to PATH.
  os-prober = prev.os-prober.override { ntfs3g = null; };
  udisks = prev.udisks.override { ntfs3g = null; };

  unstable = builtins.mapAttrs (
    name: version:
    multiverse.fast.version name version
    // {
      # fast packages omit metadata; NixOS modules need these fields for getExe
      # and module maintainers, without forcing the real derivation via .eval.
      meta = {
        mainProgram = if name == "localsend" then "localsend_app" else name;
        maintainers = [ ];
      };
    }
  ) unstableVersions;
}
