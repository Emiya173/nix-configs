# Audited hardware and planned subvolumes. Create @nixos/@nix/@snapshots in the
# installation environment and verify with nixos-generate-config before install.
# The existing Arch @ is a source for runtime data, not a rollback requirement.
{
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  device = "/dev/disk/by-uuid/98fc4f2c-cd94-4e94-810e-7757fd903ee3";
  options = [
    "compress=zstd:3"
    "noatime"
    "ssd"
    "discard=async"
  ];
  mount = subvolume: {
    inherit device;
    fsType = "btrfs";
    options = options ++ [ "subvol=${subvolume}" ];
  };
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;
  hardware.graphics = {
    enable = true;
    extraPackages = [
      pkgs.intel-media-driver
      pkgs.vpl-gpu-rt
    ];
  };
  fileSystems = {
    "/" = mount "@nixos";
    "/home" = mount "@home";
    "/nix" = mount "@nix";
    "/snapshots" = mount "@snapshots";
    "/btrfs" = {
      inherit device;
      fsType = "btrfs";
      options = [
        "subvolid=5"
        "noatime"
      ];
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/BC4C-93AB";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };
  };
  swapDevices = [ { device = "/dev/disk/by-uuid/d947850e-e0d4-424c-9f39-d489a88229cb"; } ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
