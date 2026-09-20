{ inputs }:

final: prev:

let
  unstablePkgs = import inputs.nixpkgs-unstable {
    inherit (prev.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  inherit (unstablePkgs)
    codex
    ;

  unstable = unstablePkgs;

  michi-ocr = final.callPackage ../packages/michi-ocr {
    src = inputs.michi-ocr;
  };
  voicevox-image = final.callPackage ../packages/voicevox-image.nix { };
}
