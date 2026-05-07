{ config, pkgs, ... }:

{
  # niri 详细配置见 ./niri.nix

  programs.mpv = {
    enable = true;
    config = {
      keep-open = "yes";
      hwdec = "auto-safe";
      vo = "gpu-next";
    };
  };

  programs.chromium = {
    enable = true;
    commandLineArgs = [
      # Wayland 原生 + VAAPI 硬解 (AMD)
      "--ozone-platform=wayland"
      "--enable-features=UseOzonePlatform,WaylandWindowDecorations,VaapiVideoDecodeLinuxGL"
      "--ignore-gpu-blocklist"
      # 关闭烦人的密码冒泡 (Linux 上 KWallet/Gnome-keyring 经常出问题)
      "--password-store=basic"
    ];
  };

  # 桌面用户级包
  home.packages = with pkgs; [
    # 启动器
    fuzzel
    rofi-wayland

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

    # 中文软件 (linuxqq 在 nixpkgs 里就叫 qq)
    wpsoffice-cn
    qq
    feishu
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
