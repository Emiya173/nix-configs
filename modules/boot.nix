{ config, pkgs, lib, ... }:

{
  boot = {
    kernelPackages = pkgs.linuxPackages_zen;

    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        useOSProber = true;
        configurationLimit = 20;
      };
      timeout = 5;
    };

    supportedFilesystems = [ "btrfs" "ntfs" ];

    kernel.sysctl = {
      "vm.swappiness" = 10;
    };
  };

  services.fstrim.enable = true;
}
