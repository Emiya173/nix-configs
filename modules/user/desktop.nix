{
  config,
  pkgs,
  lib,
  inputs,
  userName,
  desktopFeatures,
  displayConfig,
  ...
}:

let
  uiFontFamily = builtins.head config.fonts.fontconfig.defaultFonts.sansSerif;
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
  browserFlags = [
    "--ozone-platform-hint=wayland"
    "--gtk-version=4"
    "--ignore-gpu-blocklist"
    "--enable-features=WaylandWindowDecorations,TouchpadOverscrollHistoryNavigation,AcceleratedVideoDecodeLinuxGL,VaapiVideoDecodeLinuxGL"
    "--enable-wayland-ime"
    "--wayland-text-input-version=3"
    "--password-store=gnome-libsecret"
  ];
  browserOverrides.commandLineArgs = lib.concatStringsSep " " browserFlags;
  mpv = inputs.nix-wrapper-modules.wrappers.mpv.wrap {
    inherit pkgs;
    "mpv.conf".content = ''
      keep-open=yes
      hwdec=auto-safe
      vo=gpu-next
    '';
  };
  cursor = {
    name = "Bibata-Modern-Classic";
    size = 32;
  };
  cursorIndex = pkgs.writeText "default-cursor-index.theme" ''
    [Icon Theme]
    Name=Default
    Comment=Default Cursor Theme
    Inherits=${cursor.name}
  '';
  gtkSettings = {
    gtk-font-name = "${uiFontFamily} 11";
    gtk-icon-theme-name = "Papirus-Dark";
    gtk-cursor-theme-name = cursor.name;
    gtk-cursor-theme-size = cursor.size;
  };
  gtkTheme.gtk-theme-name = "Materia-dark";
  gtkInput.gtk-im-module = "fcitx";
  gtkIni = settings: lib.generators.toINI { } { Settings = settings; };
in
{
  hjem.users.${userName} = {
    xdg.config.files =
      lib.genAttrs (map (v: "electron${v}-flags.conf") electronVersions) (_: {
        text = electronFlags;
      })
      // {
        "feishu/fontconfig.conf".source = feishuFontConfig;
        "gtk-3.0/settings.ini".text = gtkIni (gtkSettings // gtkTheme // gtkInput);
        # DMS owns GTK CSS and Qt color files; keep their parent directories writable.
        "gtk-4.0/settings.ini".text = gtkIni (gtkSettings // gtkInput);

        # 百度网盘会用 xdg-mime/sed 替换符号链接；激活时恢复声明式关联。
        "mimeapps.list".clobber = true;

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

    xdg.mime-apps.default-applications = {
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

    xdg.data.files = {
      "applications/codex-desktop.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Codex
        Comment=Open the Codex desktop workspace
        Exec=codex-desktop %U
        Icon=chatgpt
        Terminal=false
        Categories=Development;
      '';
      "icons/default/index.theme".source = cursorIndex;
      "icons/${cursor.name}".source = "${pkgs.bibata-cursors}/share/icons/${cursor.name}";
    };

    files = {
      ".gtkrc-2.0".text = lib.concatLines (
        lib.mapAttrsToList (name: value: "${name} = ${builtins.toJSON value}") (gtkSettings // gtkTheme)
      );
      ".icons/default/index.theme".source = cursorIndex;
      ".icons/${cursor.name}".source = "${pkgs.bibata-cursors}/share/icons/${cursor.name}";
      ".Xresources".text = ''
        Xcursor.theme: ${cursor.name}
        Xcursor.size: ${toString cursor.size}
      '';
    };

    # fcitx5-rime 默认 schema 是 luna_pinyin (繁体倾向),切到小鹤双拼简体
    # double_pinyin_flypy 由 nixpkgs rime-data 提供,无需额外词库
    xdg.data.files."fcitx5/rime/default.custom.yaml".text = ''
      patch:
        schema_list:
          - schema: double_pinyin_flypy
    '';

    # double_pinyin_flypy 默认 simplification=0 (繁体),改默认为简体
    xdg.data.files."fcitx5/rime/double_pinyin_flypy.custom.yaml".text = ''
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
  };

  # 桌面用户级包
  users.users.${userName}.packages =
    with pkgs;
    [
      mpv
      (chromium.override browserOverrides)
      (brave.override browserOverrides)
      # 启动器/剪贴板/通知/电源菜单全归 DMS,不再装 fuzzel/rofi

      # 文档编辑
      typora

      # ChatGPT / Codex 桌面应用
      (pkgs.callPackage ../../packages/chatgpt-desktop { })

      # 通讯
      telegram-desktop
      element-desktop

      # 图像/媒体
      imv # 默认图片查看器 (dolphin 双击 / xdg-open)
      gthumb # 轻量编辑: 裁剪/缩放/旋转/调色/红眼/批量重命名/格式转换

      # 文件管理 (Yazi 由 modules/user/yazi.nix 安装)
      kdePackages.ark
      kdePackages.dolphin

      # DMS 负责截图，Satty 保留标注；录屏选区的 slurp 由脚本声明依赖。
      satty # 截图标注 (Mod+Shift+A 键位用)
      hyprpicker # 取色器 (Mod+Shift+C 键位用)

      # 系统监控/通知/音量面板/蓝牙: btop 走 wrappers.nix,
      # nvtop/libnotify/pavucontrol 在 system 模块,blueman 由 services.blueman 装

      # 主题
      bibata-cursors
      papirus-icon-theme
      materia-theme

      # qt6ct/qt5ct: 走 user profile 让 dolphin 等 system Qt app 能在 QT_PLUGIN_PATH 里搜到
      # qt.platformTheme 留空以保留 DMS 所需的 qt6ct 环境值，因此显式安装两代插件。
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

  qt = {
    enable = true;
    platformTheme = null;
    style = "kvantum";
  };
  environment.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt6ct";
    GTK2_RC_FILES = "$HOME/.gtkrc-2.0";
    XCURSOR_THEME = cursor.name;
    XCURSOR_SIZE = toString cursor.size;
  };
  environment.profileRelativeSessionVariables.XCURSOR_PATH = [ "/share/icons" ];

  # Defaults remain writable in the user dconf database for DMS and gsettings.
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        icon-theme = "Papirus-Dark";
        cursor-theme = cursor.name;
        gtk-theme = "Materia-dark";
        color-scheme = "prefer-dark";
      };
    }
  ];

}
