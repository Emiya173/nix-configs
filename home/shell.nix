{ config, pkgs, ... }:

{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set fish_greeting

      function starship_transient_prompt_func
          starship module character
      end
      if test "$TERM" != linux
          starship init fish | source
          enable_transience
      end

      # quickshell/DMS 终端配色 escape 序列 —— 必须 raw 注入,
      # 不能走 cat alias (bat) 否则会被画成带框文本。-s 跳过空文件
      if test -s ~/.local/state/quickshell/user/generated/terminal/sequences.txt
          command cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
      end

      fish_add_path "$HOME/.local/bin"
      fish_add_path "$HOME/.cargo/bin"
    '';

    shellAliases = {
      clear = "printf '\\033[2J\\033[3J\\033[1;1H'";
      c = "printf '\\033[2J\\033[3J\\033[1;1H'";
      ls = "eza --icons";
      l = "eza -lh --icons=auto";
      ll = "eza -lha --icons=auto --sort=name --group-directories-first";
      ld = "eza -lhD --icons=auto";
      lt = "eza --icons=auto --tree";
      vim = "nvim";
      lg = "lazygit";
      icat = "kitten icat";
      ff = "fastfetch --logo-type kitty";
      cat = "bat --paging=never";
    };

    # `y` 函数由 programs.yazi.enableFishIntegration + shellWrapperName 生成
    # (home/yazi.nix), 这里不要重复定义,否则 cd-on-quit 会被 cat alias 吃掉

    # ---- nix 工作流 abbr (空格展开,看得见再执行) ----
    shellAbbrs = {
      # nh / 系统切换 --------------------------------------------------
      nos   = "nh os switch ~/nix_migrate";              # 切换 (= apt upgrade + dotfile sync)
      nob   = "nh os build  ~/nix_migrate";              # 只 build 验证,不切换
      nor   = "nh os rollback";                          # 回上一代 (nh 独立子命令,switch 没有 --rollback flag)
      ninfo = "nh os info";                              # 看 generations 列表
      ngc   = "sudo nh clean all --keep 5 --keep-since 14d";  # GC 老 generations,留 5/14d

      # flake --------------------------------------------------
      nfu = "nix flake update ~/nix_migrate";  # 升 input
      nfc = "nix flake check  ~/nix_migrate";  # eval 自检
      nfs = "nix flake show   ~/nix_migrate";  # 看 outputs 树

      # 搜索 / 临时拉包 --------------------------------------------------
      nse   = "nh search";                  # nh search <pkg> (走本地索引,快)
      nsh   = "nix shell nixpkgs#";         # nix shell nixpkgs#<pkg> (临时 shell)
      nrun  = "nix run   nixpkgs#";         # nix run   nixpkgs#<pkg> -- args
      ndev  = "nix develop";                # 进当前目录 flake 的 devShell

      # 调试 --------------------------------------------------
      nwhy  = "nix why-depends";            # 谁拖进了某个包
      ntree = "nix-tree";                   # 交互式依赖树
      nrepl = "nix repl --expr 'import <nixpkgs> {}'";  # 进 repl 试 nix 表达式

      # niri / DMS --------------------------------------------------
      nmsg = "niri msg";                    # niri msg outputs/windows/action ...
      dipc = "dms ipc";                     # dms ipc spotlight/lock/audio ...
    };
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
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
        error_symbol   = "[ ](bold fg:244)";
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
        ahead      = " 🏎💨 ";
        behind     = " 😰 ";
        diverged   = " 😵 ";
        untracked  = " 🤷 ‍";
        stashed    = " 📦 ";
        modified   = " 📝 ";
        staged     = ''[++\($count\)](green)'';
        renamed    = " ✍️ ";
        deleted    = " 🗑 ";
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
          "Desktop"   = "  ";
          "Documents" = "  ";
          "Downloads" = "  ";
          "Music"     = " 󰎈 ";
          "Pictures"  = "  ";
          "Videos"    = "  ";
          "GitHub"    = " 󰊤 ";
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
    enable = true;
    enableFishIntegration = true;
  };

  programs.bat.enable = true;
  programs.eza.enable = true;
  programs.lazygit.enable = true;
  # yazi 由 home/yazi.nix 接管

  programs.fastfetch = {
    enable = true;
    settings = {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
      logo = {
        # 从 ~/.config/fastfetch/logo/ 中随机挑一张 (logo 目录由下面 xdg.configFile 注入)
        source = ''$(find "''${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/logo/" -name "*.png" | shuf -n 1)'';
        height = 18;
      };
      display.separator = " : ";
      modules = [
        { type = "custom"; format = "┌──────────────────────────────────────────┐"; }
        { type = "chassis"; key = "  󰇺 Chassis"; format = "{2}"; }
        { type = "os";      key = "  󰣇 OS";      format = "{2}"; keyColor = "red"; }
        { type = "kernel";  key = "   Kernel";  format = "{2}"; keyColor = "red"; }
        { type = "packages"; key = "  󰏗 Packages"; keyColor = "green"; }
        { type = "display"; key = "  󰍹 Display"; format = "{1}x{2} @ {3}Hz [{7}]"; keyColor = "green"; }
        { type = "terminal"; key = "   Terminal"; keyColor = "yellow"; }
        { type = "wm";      key = "  󱗃 WM"; format = "{2}"; keyColor = "yellow"; }
        { type = "custom"; format = "└──────────────────────────────────────────┘"; }
        "break"
        { type = "title"; key = "  "; format = "{6} {7} {8}"; }
        { type = "custom"; format = "┌──────────────────────────────────────────┐"; }
        { type = "cpu"; key = "   CPU"; format = "{1} @ {7}"; keyColor = "blue"; }
        { type = "gpu"; key = "  󰊴 GPU"; format = "{1} {2}"; keyColor = "blue"; }
        { type = "gpu"; key = "   GPU Driver"; format = "{3}"; keyColor = "magenta"; }
        { type = "memory"; key = "   Memory "; keyColor = "magenta"; }
        { type = "disk"; key = "  󱦟 Disk "; folders = "/"; keyColor = "red";
          format = "{size-used} / {size-total} ({size-percentage})"; }
        { type = "uptime"; key = "  󱫐 Uptime "; keyColor = "red"; }
        { type = "custom"; format = "└──────────────────────────────────────────┘"; }
        { type = "colors"; paddingLeft = 2; symbol = "circle"; }
        "break"
      ];
    };
  };

  # fastfetch logo 目录: programs.fastfetch 只管 config.jsonc,logo 单独 link
  xdg.configFile."fastfetch/logo".source = ../assets/fastfetch-logo;

  # btop
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "Default";
      theme_background = true;
      truecolor = true;
      vim_keys = false;
      rounded_corners = true;
      graph_symbol = "braille";
      shown_boxes = "cpu mem net proc";
      update_ms = 1300;
      proc_sorting = "cpu lazy";
      proc_per_core = true;
      proc_mem_bytes = true;
      proc_colors = true;
      proc_gradient = true;
    };
  };
}
