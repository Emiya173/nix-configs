# 占位文件 — 在新系统上首次安装时,用 nixos-generate-config 输出的真实文件替换它
#
#   sudo nixos-generate-config --root /mnt --dir /tmp/nixcfg
#   cp /tmp/nixcfg/hardware-configuration.nix \
#      /mnt/home/present/nix_migrate/hosts/present-pc/hardware-configuration.nix
#
# 现有 Arch 上的分区情况 (lsblk -f 输出):
#   nvme1n1p1  vfat   FAT32          BDCB-F864                  -> /boot
#   nvme1n1p2  swap                  76877c07-f399-4058-...     -> [SWAP]
#   nvme1n1p3  btrfs        Present  6c70dc3c-cb9a-...          -> /, /home (subvol?)
#   nvme0n1p2  ntfs (Windows)
#   nvme0n1p4  ntfs (新加卷)
#
# Btrfs 子卷布局自查: sudo btrfs subvol list /
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  # 按 nixos-generate-config 实际输出替换
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/6c70dc3c-cb9a-4899-bf8e-966826d297bb";
    fsType = "btrfs";
    # options = [ "subvol=@" "compress=zstd" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/6c70dc3c-cb9a-4899-bf8e-966826d297bb";
    fsType = "btrfs";
    # options = [ "subvol=@home" "compress=zstd" "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/BDCB-F864";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/76877c07-f399-4058-88c5-3425c5f37cdd"; }
  ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
