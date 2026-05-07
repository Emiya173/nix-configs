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
    # niri 周边
    xwayland-satellite
    swaybg
    swaylock-effects
    swayidle
    wl-clipboard
    cliphist
    grim
    slurp
    satty
    swappy
    wlr-randr
    nwg-displays
    nwg-look

    # quickshell + Qt
    quickshell
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qt5compat
    qt6.qtwayland
    qt6.qtimageformats
    qt6.qtsvg
    qt6.qtmultimedia
    qt6.qtshadertools
    qt6.qtpositioning
    qt6.qtsensors
    qt6.qttranslations
    libsForQt5.qt5.qtgraphicaleffects
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    qt6ct
    libsForQt5.qt5ct

    # 通用
    matugen
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
