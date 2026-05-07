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
  services.logind.extraConfig = ''
    HandlePowerKey=ignore
  '';

  # Flatpak (中文软件部分用 flatpak 补)
  services.flatpak.enable = true;

  # fstrim 已在 modules/boot.nix 启用

  # 让 NixOS 能跑非 Nix 编译的二进制 (animeko AppImage / 其他 ELF)
  programs.nix-ld.enable = true;
}
