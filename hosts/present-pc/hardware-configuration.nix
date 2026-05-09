# 占位文件 — 安装时用 nixos-generate-config 输出替换大部分内容,
# 但保留下面的 fileSystems 子卷布局假设 (@/@home/@nix/@snapshots)。
#
# 假设的 btrfs 布局:
#   subvol=@          -> /
#   subvol=@home      -> /home
#   subvol=@nix       -> /nix         (不快照,纯 store)
#   subvol=@snapshots -> /snapshots   (btrbk 写入)
#
# 如果现有 Arch 系统不是这个布局,迁移时需要先 rebalance:
#   sudo btrfs subvol list /                       # 看现有子卷
#   sudo btrfs subvol create /mnt/@nix             # 缺啥建啥
#   sudo rsync -aHAX /old-nix/ /mnt/@nix/          # 迁移数据
#
# 现有分区 (lsblk -f):
#   nvme1n1p1  vfat   FAT32          BDCB-F864                    -> /boot
#   nvme1n1p2  swap                  76877c07-f399-4058-...       -> [SWAP]
#   nvme1n1p3  btrfs        Present  6c70dc3c-cb9a-...            -> 多子卷
{ config, lib, pkgs, modulesPath, ... }:

let
  btrfsDevice = "/dev/disk/by-uuid/6c70dc3c-cb9a-4899-bf8e-966826d297bb";
  btrfsOpts = [ "compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async" ];
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  fileSystems."/" = {
    device = btrfsDevice;
    fsType = "btrfs";
    options = btrfsOpts ++ [ "subvol=@" ];
  };

  fileSystems."/home" = {
    device = btrfsDevice;
    fsType = "btrfs";
    options = btrfsOpts ++ [ "subvol=@home" ];
  };

  fileSystems."/nix" = {
    device = btrfsDevice;
    fsType = "btrfs";
    options = btrfsOpts ++ [ "subvol=@nix" ];
  };

  fileSystems."/snapshots" = {
    device = btrfsDevice;
    fsType = "btrfs";
    options = btrfsOpts ++ [ "subvol=@snapshots" ];
  };

  # btrfs root subvolume (id=5) —— 不是数据目录,而是给 btrbk 看到 @/@home/@snapshots
  # 这些 named subvol 用的入口。日常不用进去,只是 btrbk volume 配置指向它
  fileSystems."/btrfs" = {
    device = btrfsDevice;
    fsType = "btrfs";
    options = btrfsOpts ++ [ "subvolid=5" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/BDCB-F864";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/76877c07-f399-4058-88c5-3425c5f37cdd"; }
  ];

  # /var/lib/docker, /var/lib/libvirt/images 等高写入路径建议
  # 用 chattr +C 关 CoW 或挂成单独 nodatacow 子卷,见 modules/services.nix

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
