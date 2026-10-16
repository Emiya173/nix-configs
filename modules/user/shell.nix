{
  config,
  pkgs,
  lib,
  hostPaths,
  userName,
  ...
}:

{
  programs.fish = {
    enable = true;
    # Keep man-page completions for applications installed in the user profile.
    extraCompletionPackages = config.users.users.${userName}.packages;

    # Keep the upstream Starship hook inside the existing Linux TTY guard.
    promptInit = lib.mkMerge [
      (lib.mkBefore ''
        if test "$TERM" != linux
      '')
      (lib.mkAfter ''
        end
      '')
    ];

    interactiveShellInit = ''
      set fish_greeting

      fish_add_path "$HOME/.local/bin"
      fish_add_path "$HOME/.cargo/bin"
    '';

    shellAliases = {
      clear = "printf '\\033[2J\\033[3J\\033[1;1H'";
      c = "printf '\\033[2J\\033[3J\\033[1;1H'";
      ls = "eza --icons";
      l = "eza -lh --icons=auto";
      ll = "eza -lha --icons=auto --sort=name --group-directories-first";
      # These aliases were supplied by Home Manager's eza integration.
      la = "eza -a";
      lla = "eza -la";
      ld = "eza -lhD --icons=auto";
      lt = "eza --icons=auto --tree";
      vim = "nvim";
      lg = "lazygit";
      icat = "kitten icat";
      ff = "fastfetch --logo-type kitty";
      cat = "bat --paging=never";
    };

    # ---- nix 工作流 abbr (空格展开,看得见再执行) ----
    shellAbbrs = {
      # nh / 系统切换 (flake 路径走 NH_FLAKE,见 modules/nix.nix programs.nh) ----
      nos = "nh os switch"; # 切换 (= apt upgrade + dotfile sync)
      nob = "nh os build"; # 只 build 验证,不切换
      nor = "nixos-rollback"; # 先预览；--apply 备份 home 冲突后回退
      ninfo = "nh os info"; # 看 generations 列表
      # GC 已有 programs.nh.clean 定时器 (--keep 5 --keep-since 14d),这里是手动触发
      ngc = "sudo nh clean all --keep 5 --keep-since 14d";

      # flake --------------------------------------------------
      nfu = "nix flake update --flake ${lib.escapeShellArg hostPaths.repository}"; # 升 input (尾巴可接 input 名,如 nfu nixpkgs)
      nfc = "nix flake check ${lib.escapeShellArg hostPaths.repository}"; # 检查 flake 并构建 checks
      nfs = "nix flake show ${lib.escapeShellArg hostPaths.repository}"; # 看 outputs 树

      # 搜索 / 临时拉包 --------------------------------------------------
      nse = "nh search"; # nh search <pkg> (走本地索引,快)
      nsh = "nix shell nixpkgs#"; # nix shell nixpkgs#<pkg> (临时 shell)
      nrun = "nix run   nixpkgs#"; # nix run   nixpkgs#<pkg> -- args
      ndev = "nix develop"; # 进当前目录 flake 的 devShell

      # 调试 --------------------------------------------------
      nwhy = "nix why-depends"; # 谁拖进了某个包
      ntree = "nix-tree"; # 交互式依赖树
      nrepl = "nix repl --expr 'import <nixpkgs> {}'"; # 进 repl 试 nix 表达式

      # niri / DMS --------------------------------------------------
      nmsg = "niri msg"; # niri msg outputs/windows/action ...
      dipc = "dms ipc"; # dms ipc spotlight/lock/audio ...
    };
  };

  # 使用上游预构建的 nixos-unstable 文件索引；无需本地运行 nix-index。
  # 索引跟随 nix-index-database 的锁定版本，不包含本机 overlays。
  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
  };
  programs.nix-index-database.comma.enable = true;

  programs.starship = {
    enable = true;
    transientPrompt = {
      enable = true;
      left = "starship module character";
    };
    settings = {
      add_newline = false;
      format = ''
        $cmd_duration $directory$git_branch
          $character'';

      fill = {
        symbol = "-";
        style = "fg:245";
      };

      character = {
        success_symbol = "[ ](bold fg:243)";
        error_symbol = "[ ](bold fg:244)";
      };

      package.disabled = true;

      git_branch = {
        style = "bg: 252";
        symbol = "󰘬";
        truncation_length = 12;
        truncation_symbol = "";
        format = " 󰜥 [](bold fg:252)[$symbol $branch(:$remote_branch)](fg:235 bg:252)[ ](bold fg:252)";
      };

      git_commit = {
        commit_hash_length = 4;
        tag_symbol = " ";
      };

      git_state.format = ''[\($state( $progress_current of $progress_total)\)]($style) '';

      git_status = {
        conflicted = " 🏳 ";
        ahead = " 🏎💨 ";
        behind = " 😰 ";
        diverged = " 😵 ";
        untracked = " 🤷 ‍";
        stashed = " 📦 ";
        modified = " 📝 ";
        staged = ''[++\($count\)](green)'';
        renamed = " ✍️ ";
        deleted = " 🗑 ";
      };

      hostname = {
        ssh_only = false;
        format = "[•$hostname](bg:252 bold fg:235)[](bold fg:252)";
        trim_at = ".companyname.com";
        disabled = false;
      };

      line_break.disabled = false;

      memory_usage = {
        disabled = true;
        threshold = -1;
        symbol = " ";
        style = "bold dimmed green";
      };

      time = {
        disabled = true;
        format = ''🕙[\[ $time \]]($style) '';
        time_format = "%T";
      };

      username = {
        style_user = "bold bg:252 fg:235";
        style_root = "red bold";
        format = "[](bold fg:252)[$user]($style)";
        disabled = false;
        show_always = true;
      };

      directory = {
        home_symbol = " ";
        read_only = "  ";
        style = "bg:255 fg:240";
        truncation_length = 2;
        truncation_symbol = ".../";
        format = "[](bold fg:255)[󰉋 → $path]($style)[](bold fg:255)";
        substitutions = {
          "Desktop" = "  ";
          "Documents" = "  ";
          "Downloads" = "  ";
          "Music" = " 󰎈 ";
          "Pictures" = "  ";
          "Videos" = "  ";
          "GitHub" = " 󰊤 ";
        };
      };

      cmd_duration = {
        min_time = 0;
        format = "[](bold fg:252)[󰪢 $duration](bold bg:252 fg:235)[](bold fg:252)";
      };
    };
  };

  programs.atuin = {
    enable = true;
    # The Home Manager module kept the daemon disabled by default.
    daemon.enable = false;
    enableFishIntegration = true;
    settings = {
      auto_sync = false;
      update_check = false;
      style = "compact";
    };
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.fzf = {
    keybindings = true;
    fuzzyCompletion = true;
  };

  programs.bat.enable = true;
  users.users.${userName}.packages = [ pkgs.eza ];

}
