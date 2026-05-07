{ config, pkgs, lib, inputs, userName, hostName, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/boot.nix
    ../../modules/network.nix
    ../../modules/audio.nix
    ../../modules/graphics.nix
    ../../modules/desktop.nix
    ../../modules/input-method.nix
    ../../modules/fonts.nix
    ../../modules/locale.nix
    ../../modules/services.nix
    ../../modules/snapshots.nix
    ../../modules/users.nix
    ../../modules/packages.nix
    ../../modules/nix.nix
  ];

  networking.hostName = hostName;

  system.stateVersion = "25.05";
}
