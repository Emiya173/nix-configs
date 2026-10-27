{ sharedPkgs, ... }:

{
  # Reuse the flake's configured package set across hosts and checks.
  nixpkgs.pkgs = sharedPkgs;
}
