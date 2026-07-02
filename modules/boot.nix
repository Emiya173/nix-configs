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

        # 记住上次选择的启动项 (= GRUB_DEFAULT=saved + GRUB_SAVEDEFAULT=true)
        default = "saved";

        # Navi 主题 (从 Arch /usr/share/grub/themes/Navi 拷过来)
        theme = ../assets/grub-theme-navi;
        splashImage = ../assets/grub-theme-navi/background.png;

        # 与 Arch /etc/default/grub 的 GRUB_GFXMODE 一致 (2K 优先)
        gfxmodeEfi = "2560x1440x32,1920x1080x32,1280x1024x32,auto";
        gfxmodeBios = "2560x1440x32,1920x1080x32,1280x1024x32,auto";
        gfxpayloadEfi = "keep";
      };
      timeout = 5;
    };

    supportedFilesystems = [ "btrfs" "ntfs" ];

    kernelParams = [ "quiet" ];

    kernel.sysctl = {
      # zram 时代 swappiness 反着设: 换页去 zram 是纯内存操作 (压缩),成本远低于
      # 回收 page cache 后重读磁盘,内核文档建议 zram 场景用高值 (最高 200)
      "vm.swappiness" = 180;
    };
  };

  # zram 一级 swap (priority 5 > 磁盘分区 -1,优先用): 压缩比通常 3:1+,
  # 16G 磁盘 swap 分区降级为溢出兜底
  zramSwap.enable = true;

  services.fstrim.enable = true;
}
