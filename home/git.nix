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
    # 语法高亮 diff pager (git diff/show/log -p 自动走 delta)
    delta.enable = true;
  };

  programs.gh = {
    enable = true;
  };

  programs.lazygit = {
    enable = true;
    # lazygit 不读 git 的 pager 配置,单独指到 delta
    settings.git.paging = {
      colorArg = "always";
      pager = "delta --dark --paging=never";
    };
  };
}
