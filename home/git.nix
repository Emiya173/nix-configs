{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Emiya173";
    userEmail = "cno.101@qq.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "nvim";
    };
  };

  programs.gh = {
    enable = true;
  };

  programs.lazygit.enable = true;
}
