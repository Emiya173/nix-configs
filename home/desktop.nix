{
  config,
  pkgs,
  lib,
  nixosConfig,
  desktopFeatures,
  displayConfig,
  ...
}:

let
  uiFontFamily = builtins.head nixosConfig.fonts.fontconfig.defaultFonts.sansSerif;
  # 飞书等客户端会显式请求这些字体名，不一定使用 sans-serif。
  feishuUiFontAliases = [
    "PingFang SC"
    "PingFangSC-Regular"
    "Microsoft YaHei"
    "Microsoft YaHei UI"
    "Hiragino Sans GB"
    "Source Han Sans SC"
    "WenQuanYi Micro Hei"
    "WenQuanYi Zen Hei"
    "Helvetica Neue"
    "Tahoma"
    "Arial"
    "-apple-system"
    "BlinkMacSystemFont"
  ];
  feishuFontConfig = pkgs.writeText "feishu-fontconfig.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <include>/etc/fonts/fonts.conf</include>
      <dir>${pkgs.harmonyos-sans}/share/fonts/truetype/harmonyos-sans</dir>

      ${lib.concatMapStringsSep "\n" (family: ''
        <alias binding="strong">
          <family>${family}</family>
          <prefer><family>${uiFontFamily}</family></prefer>
        </alias>
      '') feishuUiFontAliases}

      <match target="font">
        <edit name="antialias" mode="assign"><bool>true</bool></edit>
        <edit name="hinting" mode="assign"><bool>true</bool></edit>
        <edit name="rgba" mode="assign"><const>none</const></edit>
      </match>
    </fontconfig>
  '';

  # 仅支持读取 flags 文件的 Electron 启动器会使用这些配置。
  # QQ 的参数在 overlay 中配置，飞书的参数由下面的 wrapper 注入。
  electronFlags = ''
    --ozone-platform-hint=auto
    --enable-features=WaylandWindowDecorations
    --enable-wayland-ime
    --wayland-text-input-version=3
  '';
  electronVersions = [
    ""
    "25"
    "28"
    "30"
    "32"
    "34"
    "36"
  ];
in
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
      "--enable-wayland-ime" # fcitx5 中文输入 (Wayland text-input-v3)
      "--wayland-text-input-version=3"
      "--password-store=gnome-libsecret" # GNOME Keyring 由 PAM 在登录时解锁
    ];
  };

  programs.brave = {
    enable = true;
    commandLineArgs = config.programs.chromium.commandLineArgs;
  };

  xdg.configFile =
    lib.genAttrs (map (v: "electron${v}-flags.conf") electronVersions) (_: {
      text = electronFlags;
    })
    // {
      "feishu/fontconfig.conf".source = feishuFontConfig;

      # 百度网盘会用 xdg-mime/sed 替换符号链接；激活时恢复声明式关联。
      "mimeapps.list".force = true;

      # ---- VSCode 也是 Electron,但读自己的 code-flags.conf ----
      "code-flags.conf".text = ''
        --ozone-platform-hint=wayland
        --gtk-version=4
        --ignore-gpu-blocklist
        --enable-features=TouchpadOverscrollHistoryNavigation
        --enable-wayland-ime
        --wayland-text-input-version=3
        --password-store=gnome-libsecret
      '';
    };

  # 默认应用关联 (xdg-open / 各 app 的 "用...打开" 都读这个)
  # 注意: nixpkgs 的 chromium 提供的是 chromium-browser.desktop (没有 chromium.desktop)
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "chromium-browser.desktop";
      "application/pdf" = "chromium-browser.desktop";
      "x-scheme-handler/http" = "chromium-browser.desktop";
      "x-scheme-handler/https" = "chromium-browser.desktop";
      "x-scheme-handler/about" = "chromium-browser.desktop";
      "x-scheme-handler/unknown" = "chromium-browser.desktop";
      "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
      "x-scheme-handler/baiduyunguanjia" = "baidunetdisk.desktop";

      "application/zip" = "org.kde.ark.desktop";
      "application/x-rar" = "org.kde.ark.desktop";
      "application/x-7z-compressed" = "org.kde.ark.desktop";

      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "audio/mpeg" = "mpv.desktop";
      "audio/flac" = "mpv.desktop";

      "image/png" = "imv.desktop";
      "image/jpeg" = "imv.desktop";
      "image/gif" = "imv.desktop";
      "image/webp" = "imv.desktop";
      "image/heif" = "imv.desktop";

      "text/plain" = "code.desktop";
      "inode/directory" = "org.kde.dolphin.desktop";
    };
  };

  xdg.desktopEntries.codex-desktop = {
    name = "Codex";
    comment = "Open the Codex desktop workspace";
    exec = "codex-desktop %U";
    icon = "chatgpt";
    terminal = false;
    categories = [ "Development" ];
  };

  # 桌面用户级包
  home.packages =
    with pkgs;
    [
      # 启动器/剪贴板/通知/电源菜单全归 DMS,不再装 fuzzel/rofi

      # 文档编辑
      typora

      # ChatGPT / Codex 桌面应用
      (pkgs.callPackage ../packages/chatgpt-desktop { })

      # 通讯
      telegram-desktop
      element-desktop

      # 图像/媒体 (mpv 由 programs.mpv.enable 装)
      imv # 默认图片查看器 (dolphin 双击 / xdg-open)
      gthumb # 轻量编辑: 裁剪/缩放/旋转/调色/红眼/批量重命名/格式转换

      # 文件管理 (yazi 由 home/yazi.nix programs.yazi 装)
      kdePackages.ark
      kdePackages.dolphin

      # DMS 负责截图，Satty 保留标注；录屏选区的 slurp 由脚本声明依赖。
      satty # 截图标注 (Mod+Shift+A 键位用)
      hyprpicker # 取色器 (Mod+Shift+C 键位用)

      # 系统监控/通知/音量面板/蓝牙: btop 走 programs.btop (shell.nix),
      # nvtop/libnotify/pavucontrol 在 system 模块,blueman 由 services.blueman 装

      # 主题
      bibata-cursors
      papirus-icon-theme
      materia-theme

      # qt6ct/qt5ct: 走 user profile 让 dolphin 等 system Qt app 能在 QT_PLUGIN_PATH 里搜到
      # (home-manager qt.platformTheme.name="qt6ct" 时 platformPackages 表无对应 key,不会自动装,显式补)
      qt6Packages.qt6ct
      libsForQt5.qt5ct

      # 中文软件
      # XWayland 下显式沿用主屏缩放；客户端的原生组件暂不支持 Wayland。
      (baidunetdisk.override {
        commandLineArgs = [
          "--force-device-scale-factor=${toString displayConfig.outputs.${displayConfig.primary}.scale}"
        ];
      })
      wpsoffice-cn
      unstable.qq

      # feishu 自带 chromium (Lark): 启动链 (bytedance-feishu -> feishu ->
      # .feishu-wrapped) 不读任何 flags 文件 (feishu-flags.conf 是 Arch launcher
      # 补丁,不是 chromium 行为),也不认 NIXOS_OZONE_WL,裸包只会跑 Xwayland。
      # 包一层注入 ozone flags;desktop Exec 原本直接指 store 启动脚本,一并改指 wrapper
      (symlinkJoin {
        name = "feishu-wayland";
        paths = [ feishu ];
        nativeBuildInputs = [ makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/bytedance-feishu \
            --set FONTCONFIG_FILE "${feishuFontConfig}" \
            --add-flags "--ozone-platform-hint=auto" \
            --add-flags "--enable-features=WaylandWindowDecorations" \
            --add-flags "--enable-wayland-ime" \
            --add-flags "--wayland-text-input-version=3" \
            --add-flags "--disable-font-subpixel-positioning"
          rm $out/share/applications/bytedance-feishu.desktop
          substitute ${feishu}/share/applications/bytedance-feishu.desktop \
            $out/share/applications/bytedance-feishu.desktop \
            --replace-fail "Exec=${feishu}/opt/bytedance/feishu/bytedance-feishu" \
                           "Exec=$out/bin/bytedance-feishu"
        '';
      })
    ]
    ++ lib.optionals desktopFeatures.entertainment [
      pkgs.blender
      pkgs.qbittorrent
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
    # cursorTheme 由 home.pointerCursor 统一管 (覆盖 GTK + XCursor + Wayland)
    # 不要用 GTK_IM_MODULE env (GTK4 已不读),改写 settings.ini
    gtk3.extraConfig.gtk-im-module = "fcitx";
    # GTK4 主题/css 全交 DMS 写: ~/.config/gtk-4.0/{gtk,dank-colors}.css
    # gtk4.theme=null = 26.05 新默认: hm 不写 gtk-4.0/gtk.css,
    # 不跟 DMS 同名文件打架 (legacy 默认是 config.gtk.theme,会写 gtk.css)
    gtk4 = {
      extraConfig.gtk-im-module = "fcitx";
      theme = null;
    };
  };

  # Qt 主题全交 DMS: DMS 动态生成
  #   ~/.config/qt6ct/qt6ct.conf    (kvantum + DankMatugen colors；字体由 fonts.nix 同步)
  #   ~/.config/Kvantum/MaterialAdw (kvantum 主题本体)
  #   ~/.local/share/color-schemes/DankMatugen*.colors (Matugen 色板)
  # (kdeglobals 是 Arch HyDE 残留, DMS 不写; KDE 应用 "默认" 配色渲染有问题,
  # 用户工作流是在 dolphin 顶部 Settings → Color Scheme 手动选其他主题)
  # 显式 "qt6ct" 而不是 "qtct" —— home-manager 把 "qtct" 映射成 QT_QPA_PLATFORMTHEME=qt5ct,
  # 而 DMS shell 内部强校验 QT_QPA_PLATFORMTHEME ∈ {gtk3, qt6ct},不满足就在 UI 弹告警。
  qt = {
    enable = true;
    platformTheme.name = "qt6ct";
    style.name = "kvantum";
  };

  # 鼠标指针统一走 home.pointerCursor (会同时塞 GTK + XCursor + Wayland)
  # 单靠 gtk.cursorTheme 不会传给 Qt/Wayland,dolphin 里指针还是默认 Adwaita
  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 32;
    gtk.enable = true;
    x11.enable = true;
  };

  # DMS "System Default" 主题靠 gsettings 取值 (SettingsData.qml:1644)
  # 没设值 → DMS 拿不到 -> updateGtkIconTheme 提前 return -> GTK 应用图标也散架
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      icon-theme = "Papirus-Dark";
      cursor-theme = "Bibata-Modern-Classic";
      gtk-theme = "Materia-dark";
      color-scheme = "prefer-dark";
    };
  };

  # fcitx5-rime 默认 schema 是 luna_pinyin (繁体倾向),切到小鹤双拼简体
  # double_pinyin_flypy 由 nixpkgs rime-data 提供,无需额外词库
  home.file.".local/share/fcitx5/rime/default.custom.yaml".text = ''
    patch:
      schema_list:
        - schema: double_pinyin_flypy
  '';

  # double_pinyin_flypy 默认 simplification=0 (繁体),改默认为简体
  home.file.".local/share/fcitx5/rime/double_pinyin_flypy.custom.yaml".text = ''
    patch:
      switches:
        - name: ascii_mode
          reset: 0
          states: [ 中文, 西文 ]
        - name: full_shape
          states: [ 半角, 全角 ]
        - name: simplification
          reset: 1
          states: [ 漢字, 汉字 ]
        - name: extended_charset
          states: [ 常用, 增廣 ]
  '';
}
