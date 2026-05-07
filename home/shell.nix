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

      # quickshell 终端配色 (迁移期间可能没有,加判断)
      if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
          cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
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

    functions = {
      y = ''
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        yazi $argv --cwd-file="$tmp"
        if test -f "$tmp"
            set cwd (cat -- "$tmp")
            if test -n "$cwd" -a "$cwd" != "$PWD"
                cd -- "$cwd"
            end
        end
        rm -f -- "$tmp"
      '';
    };
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
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

  programs.fastfetch.enable = true;
}
