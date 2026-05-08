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
      "--ozone-platform-hint=wayland"
      "--gtk-version=4"
      "--ignore-gpu-blocklist"
      "--enable-features=WaylandWindowDecorations,TouchpadOverscrollHistoryNavigation,AcceleratedVideoDecodeLinuxGL,VaapiVideoDecodeLinuxGL"
      "--enable-wayland-ime"                # fcitx5 中文输入 (Wayland text-input-v3)
      "--wayland-text-input-version=3"
      "--password-store=gnome-libsecret"    # 需要 gnome-keyring (已在 niri spawn 启动)
      "--disable-features=ExtensionManifestV2Unsupported"
    ];
  };

  # ---- 其他 Electron 应用全局 flags (telegram/element/feishu/linuxqq/wpsoffice...) ----
  # ~/.config/electron-flags.conf 是 Electron 通用约定,所有不带专属 wrapper 的 Electron 都会读
  xdg.configFile."electron-flags.conf".text = ''
    --ozone-platform-hint=auto
    --enable-features=WaylandWindowDecorations
    --enable-wayland-ime
    --wayland-text-input-version=3
  '';

  # 不同主版本 Electron 也读各自版本号文件,batch 写一份避免漏
  xdg.configFile."electron25-flags.conf".text = config.xdg.configFile."electron-flags.conf".text;
  xdg.configFile."electron28-flags.conf".text = config.xdg.configFile."electron-flags.conf".text;
  xdg.configFile."electron30-flags.conf".text = config.xdg.configFile."electron-flags.conf".text;
  xdg.configFile."electron32-flags.conf".text = config.xdg.configFile."electron-flags.conf".text;
  xdg.configFile."electron34-flags.conf".text = config.xdg.configFile."electron-flags.conf".text;
  xdg.configFile."electron36-flags.conf".text = config.xdg.configFile."electron-flags.conf".text;

  # ---- VSCode 也是 Electron,但读自己的 code-flags.conf ----
  xdg.configFile."code-flags.conf".text = ''
    --ozone-platform-hint=wayland
    --gtk-version=4
    --ignore-gpu-blocklist
    --enable-features=TouchpadOverscrollHistoryNavigation
    --enable-wayland-ime
    --wayland-text-input-version=3
    --password-store=gnome-libsecret
  '';

  # 桌面用户级包
  home.packages = with pkgs; [
    # 启动器/剪贴板/通知/电源菜单全归 DMS,不再装 fuzzel/rofi

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

    # 截图/取色 (DMS 不提供这些)
    grim          # 屏幕抓取
    slurp         # 区域选择
    satty         # 截图标注 (Mod+Shift+A 键位用)
    hyprpicker    # 取色器 (Mod+Shift+C 键位用)

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
    # 不要用 GTK_IM_MODULE env (GTK4 已不读),改写 settings.ini
    gtk3.extraConfig.gtk-im-module = "fcitx";
    gtk4 = {
      extraConfig.gtk-im-module = "fcitx";
      theme = config.gtk.theme;   # 显式继承,silence 26.05 warning
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
  };
}
