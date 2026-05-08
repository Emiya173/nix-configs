{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.name = "Emiya173";
      user.email = "cno.101@qq.com";
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
