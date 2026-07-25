{ inputs }:

_final: prev:

let
  unstablePkgs = import inputs.nixpkgs-unstable {
    inherit (prev.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  inherit (unstablePkgs)
    claude-code
    codex
    ;

  unstable = unstablePkgs;
}
