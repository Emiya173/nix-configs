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
  ];

  home.username = "present";
  home.homeDirectory = "/home/present";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  xdg.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "chromium";
    TERMINAL = "kitty";
  };
}
