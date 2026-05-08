{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./shell.nix
    ./kitty.nix
    ./git.nix
    ./packages.nix
    ./desktop.nix
    ./niri.nix
    ./dev.nix
    ./nvim.nix
    ./yazi.nix
  ];

  home.username = "present";
  home.homeDirectory = "/home/present";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  xdg = {
    enable = true;

    # 对应 Arch ~/.config/user-dirs.dirs (英文路径)
    userDirs = {
      enable = true;
      createDirectories = true;
      setSessionVariables = true;   # 26.05 默认改成 false,我们显式保留旧行为(让 $XDG_*_DIR 进 env)
      desktop     = "${config.home.homeDirectory}/Desktop";
      documents   = "${config.home.homeDirectory}/Documents";
      download    = "${config.home.homeDirectory}/Downloads";
      music       = "${config.home.homeDirectory}/Music";
      pictures    = "${config.home.homeDirectory}/Pictures";
      videos      = "${config.home.homeDirectory}/Videos";
      templates   = "${config.home.homeDirectory}/Templates";
      publicShare = "${config.home.homeDirectory}/Public";
    };

    # 对应 ~/.config/mimeapps.list 默认应用绑定
    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/pdf"           = "chromium.desktop";
        "application/zip"           = "org.kde.ark.desktop";
        "application/x-rar"         = "org.kde.ark.desktop";
        "application/x-7z-compressed" = "org.kde.ark.desktop";
        "image/jpeg"                = "imv.desktop";
        "image/png"                 = "imv.desktop";
        "image/heif"                = "imv.desktop";
        "image/webp"                = "imv.desktop";
        "image/gif"                 = "imv.desktop";
        "video/mp4"                 = "mpv.desktop";
        "video/x-matroska"          = "mpv.desktop";
        "video/webm"                = "mpv.desktop";
        "audio/mpeg"                = "mpv.desktop";
        "audio/flac"                = "mpv.desktop";
        "inode/directory"           = "org.kde.dolphin.desktop";
        "text/html"                 = "chromium.desktop";
        "text/plain"                = "code.desktop";
        "x-scheme-handler/http"     = "chromium.desktop";
        "x-scheme-handler/https"    = "chromium.desktop";
        "x-scheme-handler/tonsite"  = "org.telegram.desktop.desktop";
      };
    };
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "chromium";
    TERMINAL = "kitty";
  };
}
