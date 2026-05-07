{ config, pkgs, ... }:

{
  # niri 配置
  # 详细 KDL 配置先放在 ./niri/config.kdl,然后这里 link
  # xdg.configFile."niri/config.kdl".source = ./niri/config.kdl;

  programs.niri = {
    settings = {
      input = {
        keyboard.xkb.layout = "us";
        touchpad = {
          tap = true;
          natural-scroll = true;
        };
      };

      layout = {
        gaps = 8;
        center-focused-column = "never";
        preset-column-widths = [
          { proportion = 0.33333; }
          { proportion = 0.5; }
          { proportion = 0.66667; }
        ];
      };

      spawn-at-startup = [
        { command = [ "xwayland-satellite" ]; }
        { command = [ "swaybg" "-i" "${config.home.homeDirectory}/Pictures/wallpaper.jpg" "-m" "fill" ]; }
      ];

      environment = {
        DISPLAY = ":0";
        QT_QPA_PLATFORMTHEME = "qt6ct";
        XCURSOR_THEME = "Bibata-Modern-Classic";
      };

      binds = with config.lib.niri.actions; {
        "Mod+Return".action = spawn "kitty";
        "Mod+D".action = spawn "fuzzel";
        "Mod+Q".action = close-window;
        "Mod+L".action = spawn "swaylock";
        "Mod+Shift+E".action = quit;

        "Mod+Left".action = focus-column-left;
        "Mod+Right".action = focus-column-right;
        "Mod+Up".action = focus-window-up;
        "Mod+Down".action = focus-window-down;

        "Mod+Shift+Left".action = move-column-left;
        "Mod+Shift+Right".action = move-column-right;
        "Mod+Shift+Up".action = move-window-up;
        "Mod+Shift+Down".action = move-window-down;

        "Mod+1".action = focus-workspace 1;
        "Mod+2".action = focus-workspace 2;
        "Mod+3".action = focus-workspace 3;
        "Mod+4".action = focus-workspace 4;
        "Mod+5".action = focus-workspace 5;

        "Mod+R".action = switch-preset-column-width;
        "Mod+F".action = maximize-column;
        "Mod+Shift+F".action = fullscreen-window;

        "Print".action = screenshot;
        "Ctrl+Print".action = screenshot-screen;
        "Alt+Print".action = screenshot-window;
      };
    };
  };

  # 可选的浏览/工具
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
