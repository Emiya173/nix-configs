{
  lib,
  pkgs,
  userName,
  ...
}:

{
  users.users.${userName}.packages = with pkgs; [
    delta
    gh
  ];

  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "nvim";

      # Match Home Manager's delta integration, including interactive staging.
      pager = lib.genAttrs [ "blame" "diff" "log" "show" ] (_: lib.getExe pkgs.delta);
      interactive.diffFilter = "${lib.getExe pkgs.delta} --color-only";
      credential = lib.genAttrs [ "https://github.com" "https://gist.github.com" ] (_: {
        helper = [
          ""
          "${lib.getExe pkgs.gh} auth git-credential"
        ];
      });
    };
  };

  programs.lazygit = {
    enable = true;
    settings = {
      # 使用当前 pagers schema，避免自动迁移尝试写入只读配置文件。
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
