{ config, pkgs, lib, userName, ... }:

{
  # Docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
    autoPrune.enable = true;
  };

  # Waydroid
  virtualisation.waydroid.enable = true;

  # Sunshine 串流
  services.sunshine = {
    enable = true;
    autoStart = false;
    capSysAdmin = true;
    openFirewall = true;
  };

  # 自动挂载 NTFS / U 盘
  services.udisks2.enable = true;

  # 防止笔记本盖子或电源键意外关机的策略 (台式可酌情)
  services.logind.settings.Login.HandlePowerKey = "ignore";

  # Flatpak (中文软件部分用 flatpak 补)
  services.flatpak.enable = true;

  # fstrim 已在 modules/boot.nix 启用

  # 让 NixOS 能跑非 Nix 编译的二进制 (animeko AppImage / 其他 ELF)
  programs.nix-ld.enable = true;

  # AppImage: binfmt=true 注册 binfmt_misc,双击/直接 ./xxx.AppImage 自动走 appimage-run
  # (extract -> 在 FHS 沙盒里跑)。配合上面 nix-ld 一起,绝大多数 AppImage 不用手动 chmod+
  # appimage-run 拼命令了。
  programs.appimage = {
    enable = true;
    binfmt = true;
  };
}
