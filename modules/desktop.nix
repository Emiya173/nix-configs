{
  config,
  pkgs,
  lib,
  inputs,
  displayConfig,
  ...
}:

let
  primaryDisplay = displayConfig.outputs.${displayConfig.primary};
  primaryMode = primaryDisplay.mode;
  # 沿用 Candy 当前壁纸；直接引用 store 资源，登录器不依赖用户目录权限。
  greeterWallpaper = ../assets/sddm-theme-candy/backgrounds/seele.png;
  # configFiles 按 basename 复制，writeTextDir 保留 session.json 的确切文件名。
  greeterSession = pkgs.writeTextDir "session.json" (
    builtins.toJSON {
      wallpaperPath = "${greeterWallpaper}";
    }
  );
  # 原生 greeter 模块直接启动 Quickshell，需补齐 DMS CLI 包装器提供的 Qt 路径。
  greeterQtPackages = with pkgs.kdePackages; [
    kirigami.unwrapped
    sonnet
    qtmultimedia
    qtimageformats
    kimageformats
  ];
  greeterQuickshell =
    pkgs.runCommand "quickshell-dms-greeter"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "quickshell";
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${lib.getExe pkgs.quickshell} $out/bin/quickshell \
          --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${
            lib.escapeShellArg (
              lib.concatMapStringsSep ":" (p: "${p}/${pkgs.qt6.qtbase.qtQmlPrefix}") greeterQtPackages
            )
          } \
          --prefix QT_PLUGIN_PATH : ${
            lib.escapeShellArg (
              lib.concatMapStringsSep ":" (p: "${p}/${pkgs.qt6.qtbase.qtPluginPrefix}") greeterQtPackages
            )
          }
        ln -s quickshell $out/bin/qs
      '';
  greeter = config.services.displayManager.dms-greeter;
  greeterLauncher = pkgs.writeShellScript "dms-greeter-start" ''
    # The upstream launcher appends these to PATH. A system-wide qs installed
    # by the desktop module would then shadow the wrapper's Qt dependencies.
    export PATH=${
      lib.makeBinPath [
        greeterQuickshell
        pkgs.niri
      ]
    }:"$PATH"
    exec ${lib.getExe pkgs.bash} ${greeter.package}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter \
      --cache-dir /var/lib/dms-greeter --command niri \
      -p ${greeter.package}/share/quickshell/dms \
      -C ${pkgs.writeText "dmsgreeter-compositor-config" greeter.compositor.customConfig} "$@"
  '';
in
{
  # niri-flake 随会话启动 KDE Polkit agent；保持单一认证代理。
  programs.niri.enable = true;

  services.displayManager.dms-greeter = {
    enable = true;
    package = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.default;
    quickshell.package = greeterQuickshell;
    configFiles = [ "${greeterSession}/session.json" ];
    compositor = {
      name = "niri";
      # 登录时只点亮主屏；用户会话启动后再加载 modules/user/niri.nix 的完整布局。
      customConfig = ''
        hotkey-overlay { skip-at-startup; }
        gestures { hot-corners { off; }; }
        layout { background-color "#000000"; }

        output "${displayConfig.primary}" {
          mode "${toString primaryMode.width}x${toString primaryMode.height}@${toString primaryMode.refresh}"
          scale ${toString primaryDisplay.scale}
          position x=0 y=0
          focus-at-startup
        }
        ${lib.concatMapStringsSep "\n"
          (output: ''
            output "${output}" { off; }
          '')
          (lib.filter (output: output != displayConfig.primary) (builtins.attrNames displayConfig.outputs))
        }
      '';
    };
  };

  services.greetd.settings.default_session.command = lib.mkForce "${greeterLauncher}";
  # Also expose the exact launcher to the build-time greeter smoke check.
  system.build.greeter-launcher = greeterLauncher;

  programs.dconf.enable = true;

  # DMS 通过 AccountsService 持久化用户头像；缺少服务时只在当前进程中生效。
  services.accounts-daemon.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
    config.niri = {
      default = [
        "gnome"
        "gtk"
      ];
      # gnome portal 不自带 FileChooser,会委托给 nautilus;没装 nautilus 就
      # 报 "The name is not activatable",表现为应用里点上传/打开文件没反应。
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    };
  };

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.tumbler.enable = true; # 文件管理器视频/PDF/字体缩略图
  programs.kdeconnect.enable = false;

  # gnome-keyring + PAM 自动解锁 (登入时用登录密码解 login keyring)
  # chromium --password-store=gnome-libsecret / git credential / ssh 私钥都走这个
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;

  environment.systemPackages = with pkgs; [
    # niri 周边 (DMS 已接管 wallpaper/clipboard 面板/launcher/通知/电源菜单)
    xwayland-satellite
    wl-clipboard # CLI 脚本备用 (wl-copy/wl-paste)
    wlr-randr
    nwg-displays
    nwg-look
    brightnessctl # DMS 走 dms ipc brightness,这里留 CLI 兜底

    # DMS "System Default" 主题靠 gsettings get org.gnome.desktop.interface icon-theme
    # gsettings 二进制已经被其他包 (glib-bin) 间接拉进 PATH,只差 schema
    gsettings-desktop-schemas

    # Qt 主题链: DMS 写 qt6ct.conf + Kvantum/MaterialAdw,kvantum style 是系统级
    # qt6ct/qt5ct 不能放 system —— 它们的 platformtheme 插件得在 user 的 QT_PLUGIN_PATH
    # (/etc/profiles/per-user/...) 里 dolphin 才搜得到,system 路径不会被搜。
    # 见 modules/user/desktop.nix 中的用户包。
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.breeze-icons # 图标兜底 (Papirus / OneUI 没覆盖的 KDE 自家图标)
    kdePackages.qqc2-desktop-style # QtQuick Controls 2 走桌面风格

    # dolphin 缩略图: 视频 / 图片 / PDF / 字体 / 漫画书 / ePub 等
    kdePackages.kio-extras
    kdePackages.kdegraphics-thumbnailers
    kdePackages.ffmpegthumbs

    libnotify
  ];

}
