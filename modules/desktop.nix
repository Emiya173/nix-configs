{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # 从 Arch HyDE 带过来的 Candy 主题,QML 里 QtGraphicalEffects 已替换为 Qt5Compat.GraphicalEffects
  sddm-candy = pkgs.stdenv.mkDerivation {
    name = "sddm-theme-candy";
    src = ../assets/sddm-theme-candy;
    installPhase = ''
      dst=$out/share/sddm/themes/Candy
      mkdir -p $dst
      cp -r ./* $dst/
      # 原仓库没附带 metadata.desktop —— sddm 没这个文件就识别不到主题,
      # 报 "theme not found / missing resources",这里补上
      cat > $dst/metadata.desktop <<EOF
      [SddmGreeterTheme]
      Name=Candy
      Description=Candy (HyDE)
      Type=sddm-theme
      Version=0.1
      MainScript=Main.qml
      ConfigFile=theme.conf
      QtVersion=6
      EOF
    '';
  };
in
{
  programs.niri.enable = true;
  programs.niri.package = pkgs.niri;

  services.displayManager.sddm = {
    enable = true;
    # wayland greeter 需要额外 wayland 合成器 (kwin_wayland 等),没装直接起不来,关掉
    wayland.enable = false;
    theme = "Candy";
    # Candy QML import: QtQuick.Controls 2.4 / Qt5Compat.GraphicalEffects /
    # QtQuick.VirtualKeyboard 2.3 —— 都要塞 QML 模块路径
    extraPackages = with pkgs.kdePackages; [
      qtdeclarative
      qt5compat
      qtvirtualkeyboard
      qtsvg
    ];
  };

  services.xserver.enable = true;
  # SDDM 走 X11 模式,greeter 显示在 Xorg primary output 上 —— 钉到 DP-1 (主屏)
  services.xserver.xrandrHeads = [
    { output = "DP-1"; primary = true; }
    { output = "DP-2"; }
  ];
  # xrandrHeads 只写 xorg.conf 的 Monitor/Screen section,amdgpu modesetting 经常不认。
  # 仅设 --primary 也不移动 greeter —— sddm-greeter 走 Qt primaryScreen,
  # 但 amdgpu 默认把 DP-2 排到 (0,0) -> greeter 还是落副屏。
  # 直接在 SDDM 阶段关掉 DP-2,让 greeter 只能落主屏;登入后 niri 自己重新
  # 按 outputs 配置点亮 DP-2 + 旋转 + 摆位。
  services.xserver.displayManager.setupCommands = ''
    ${pkgs.xrandr}/bin/xrandr --output DP-2 --off || true
    ${pkgs.xrandr}/bin/xrandr --output DP-1 --primary --auto || true
  '';

  programs.dconf.enable = true;

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
  security.pam.services.sddm.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;

  environment.systemPackages = with pkgs; [
    sddm-candy # 自打包的 Candy 主题 (let 里定义)

    # niri 周边 (DMS 已接管 wallpaper/clipboard 面板/launcher/通知/电源菜单)
    xwayland-satellite
    wl-clipboard # CLI 脚本备用 (wl-copy/wl-paste)
    wlr-randr
    nwg-displays
    nwg-look
    brightnessctl # DMS 走 dms ipc brightness,这里留 CLI 兜底

    # Qt 主题 (DMS quickshell 自身不依赖 Kvantum,但 dolphin/ark 等仍需要)
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    qt6Packages.qt6ct # 顶层 qt6ct 已 deprecated
    libsForQt5.qt5ct
    kdePackages.breeze-icons       # 图标兜底 (Papirus / OneUI 没覆盖的 KDE 自家图标)
    kdePackages.qqc2-desktop-style # QtQuick Controls 2 走桌面风格

    # dolphin 缩略图: 视频 / 图片 / PDF / 字体 / 漫画书 / ePub 等
    kdePackages.kio-extras
    kdePackages.kdegraphics-thumbnailers
    kdePackages.ffmpegthumbs

    libnotify
    polkit_gnome # DMS 不提供 polkit agent
  ];

  # niri 不带 polkit agent,用 gnome 的
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
}
