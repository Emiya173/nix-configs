{
  config,
  pkgs,
  lib,
  displayConfig,
  userName,
  ...
}:
let
  primary = displayConfig.outputs.${displayConfig.primary};
in
{
  programs.umbriel.enable = true;
  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
    systemd.enable = true;
  };
  systemd.user.services.noctalia.unitConfig.ConditionUser = userName;
  programs.luciole.enable = true;
  environment.etc."xdg/noctalia/config.toml".text = ''
    [shell]
    polkit_agent = true
  '';

  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "Umbriel";
      user.default = userName;
      appearance.wallpaper.path = "${../assets/sddm-theme-candy/backgrounds/seele.png}";
      output = {
        name = displayConfig.primary;
        inherit (primary.mode) width height;
        refresh_rate = primary.mode.refresh;
        inherit (primary) scale;
      };
      cursor = {
        theme = "Bibata-Modern-Classic";
        path = "${pkgs.bibata-cursors}";
        size = 32;
      };
    };
  };
  systemd.services.greetd.serviceConfig.Type = lib.mkForce "simple";

  programs.dconf.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.tumbler.enable = true;
  xdg.portal = {
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      config.programs.luciole.package
    ];
    config.umbriel."org.freedesktop.impl.portal.FileChooser" = [ "luciole" ];
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;

  environment.systemPackages = with pkgs; [
    wl-clipboard
    wlr-randr
    nwg-look
    brightnessctl
    gsettings-desktop-schemas
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.breeze-icons
    kdePackages.qqc2-desktop-style
    libnotify
  ];
}
