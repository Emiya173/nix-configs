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

  # 语法高亮 diff pager;enableGitIntegration 写进 git config 的 core.pager
  # (原 programs.git.delta 已改名为顶层 programs.delta)
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  programs.gh = {
    enable = true;
  };

  programs.lazygit = {
    enable = true;
    # lazygit 不读 git 的 pager 配置,单独指到 delta
    # (新版 schema: git.paging 对象已改为 git.pagers 数组,旧写法会触发
    # 自动迁移并因 hm 只读 symlink 报 read-only file system)
    settings.git.pagers = [
      {
        colorArg = "always";
        pager = "delta --dark --paging=never";
      }
    ];
  };
}
