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
    # niri 周边 (DMS 已自带 quickshell / matugen / cliphist 等;此处只放它没覆盖的)
    xwayland-satellite
    swaybg
    wl-clipboard
    grim
    slurp
    satty
    swappy
    wlr-randr
    nwg-displays
    nwg-look
    brightnessctl

    # Qt 主题 (Kvantum + qt*ct, DMS 自身的 quickshell 不依赖 Kvantum,
    # 但其它 Qt 应用 (dolphin/ark/kdiskmark 等) 仍需要)
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    qt6ct
    libsForQt5.qt5ct

    libnotify
    polkit_gnome
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
