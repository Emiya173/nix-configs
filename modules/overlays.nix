{ inputs, ... }:

{
  nixpkgs.overlays = [
    (import ../overlays/default.nix { inherit inputs; })
  ];
}
