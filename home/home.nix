{ config, pkgs, lib, inputs, userName, ... }:

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

  home.username = userName;
  home.homeDirectory = "/home/${userName}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  xdg = {
    enable = true;

    # 对应 Arch ~/.config/user-dirs.dirs — 各路径 (英文) 就是 home-manager 默认值,只写覆盖项
    userDirs = {
      enable = true;
      createDirectories = true;
      setSessionVariables = true;   # 26.05 默认改成 false,我们显式保留旧行为(让 $XDG_*_DIR 进 env)
    };

    # mimeApps 统一在 home/desktop.nix 声明 (单一来源,避免两处合并出重复条目)
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "chromium";
    TERMINAL = "kitty";
  };
}
