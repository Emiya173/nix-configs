{
  config,
  pkgs,
  lib,
  inputs,
  userName,
  hostName,
  ...
}:

let
  hostPaths = import ./paths.nix { inherit userName; };
in
{
  _module.args.hostPaths = hostPaths;
  home-manager.extraSpecialArgs = { inherit hostPaths; };

  imports = [
    ./hardware-configuration.nix
    ../../modules/boot.nix
    ../../modules/network.nix
    ../../modules/audio.nix
    ../../modules/graphics.nix
    ../../modules/desktop.nix
    ../../modules/input-method.nix
    ../../modules/keyd.nix
    ../../modules/fonts.nix
    ../../modules/locale.nix
    ../../modules/services.nix
    ../../modules/snapshots.nix
    ../../modules/gaming.nix
    ../../modules/users.nix
    ../../modules/packages.nix
    ../../modules/nix.nix
    ../../modules/overlays.nix
  ];

  networking.hostName = hostName;

  system.stateVersion = "25.11";
}
