{ config, pkgs, lib, inputs, ... }:

{
  programs.niri.enable = true;

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "breeze";
  };

  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
    config.niri = {
      default = [ "gnome" "gtk" ];
    };
  };

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  programs.kdeconnect.enable = false;

  environment.systemPackages = with pkgs; [
    # niri 周边 (DMS 已接管 wallpaper/clipboard 面板/launcher/通知/电源菜单)
    xwayland-satellite
    wl-clipboard               # CLI 脚本备用 (wl-copy/wl-paste)
    wlr-randr
    nwg-displays
    nwg-look
    brightnessctl              # DMS 走 dms ipc brightness,这里留 CLI 兜底

    # Qt 主题 (DMS quickshell 自身不依赖 Kvantum,但 dolphin/ark 等仍需要)
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    qt6ct
    libsForQt5.qt5ct

    libnotify
    polkit_gnome               # DMS 不提供 polkit agent
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
