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
    settings = {
      # 使用当前 pagers schema，避免自动迁移尝试写入 Home Manager 只读文件。
      git.pagers = [
        {
          colorArg = "always";
          pager = "delta --dark --paging=never";
        }
      ];

      # 保留迁移前的 Gerrit 推送快捷键和终端剪贴板配置。
      customCommands = [
        {
          key = "G";
          command = "git push {{.SelectedLocalBranch.UpstreamRemote}} HEAD:refs/for/{{.SelectedLocalBranch.UpstreamBranch}}";
          context = "localBranches";
          description = "Push to Gerrit for review";
        }
      ];
      os.copyToClipboardCmd = ''printf "\033]52;c;$(printf '%s' {{text}} | base64 -w 0)\a" > /dev/tty'';
    };
  };
}
