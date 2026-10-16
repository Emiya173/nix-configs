{ ... }:
{
  imports = [
    ./shell.nix
    ./git.nix
    ./dev.nix
    ./packages.nix
    ./nvim.nix
    ./yazi.nix
    ./wrappers.nix
    ./niri.nix
    ./desktop.nix
    ./fonts.nix
    ./home.nix
  ];
  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "chromium";
    TERMINAL = "kitty";
  };
}
