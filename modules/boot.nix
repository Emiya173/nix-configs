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
      "vm.swappiness" = 10;
    };
  };

  services.fstrim.enable = true;
}
