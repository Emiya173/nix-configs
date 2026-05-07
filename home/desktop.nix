{ config, pkgs, ... }:

{
  # niri 详细配置见 ./niri.nix

  programs.firefox.enable = true;

  # 桌面用户级包
  home.packages = with pkgs; [
    # 启动器
    fuzzel
    rofi-wayland

    # 浏览器
    chromium

    # 通讯
    telegram-desktop
    element-desktop

    # 图像/媒体
    mpv
    imv
    qbittorrent

    # 文件管理
    yazi
    kdePackages.ark
    kdePackages.dolphin

    # 截图/取色
    grim
    slurp
    satty
    swappy
    hyprpicker

    # 系统监控
    nvtopPackages.amd
    btop

    # 其他
    libnotify
    pavucontrol
    blueman

    # 主题
    bibata-cursors
    papirus-icon-theme
    materia-theme

    # 中文软件
    wpsoffice-cn
    # linuxqq        # 通过 nixpkgs (有时会缺) - 见 README,可改 flatpak
    # feishu         # nixpkgs 暂无 - 见 README, 用 flatpak 或 AppImage
  ];

  # GTK / Qt 主题
  gtk = {
    enable = true;
    theme = {
      name = "Materia-dark";
      package = pkgs.materia-theme;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
  };
}
