{
  config,
  pkgs,
  lib,
  inputs,
  userName,
  hostName,
  ...
}:

{
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

  # Keep Proton prefixes and saves on Btrfs while retaining Steam's library path.
  # Populate the source from the existing compatdata before the first activation.
  fileSystems."/mnt/SteamLibrary/steamapps/compatdata" = {
    device = "/home/${userName}/.local/share/steam-compatdata/ntfs-library";
    fsType = "none";
    options = [
      "bind"
      "nofail"
    ];
    depends = [
      "/home"
      "/mnt"
    ];
    noCheck = true;
  };

  system.stateVersion = "25.11";
}
