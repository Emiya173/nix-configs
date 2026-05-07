{ config, pkgs, lib, ... }:

{
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    shellWrapperName = "y";   # 与你 fish 里 `y` 函数一致

    settings = {
      mgr = {
        ratio = [ 1 4 3 ];
        sort_by = "natural";
        sort_dir_first = true;
        show_hidden = false;
        show_symlink = true;
      };

      preview = {
        max_width = 600;
        max_height = 900;
        cache_dir = "";
        image_filter = "lanczos3";
        image_quality = 75;
      };

      opener = {
        edit = [
          { run = "$EDITOR \"$@\""; block = true; for = "unix"; }
        ];
        open = [
          { run = "xdg-open \"$@\""; orphan = true; for = "linux"; }
        ];
        play = [
          { run = "mpv --force-window \"$@\""; orphan = true; for = "linux"; }
        ];
        view-image = [
          { run = "imv \"$@\""; orphan = true; for = "linux"; }
        ];
      };

      open.rules = [
        { name = "*.{jpg,jpeg,png,gif,webp,bmp,svg}"; use = [ "view-image" "open" ]; }
        { name = "*.{mp4,mkv,webm,mov,avi}"; use = [ "play" "open" ]; }
        { name = "*.{mp3,flac,wav,ogg,m4a}"; use = [ "play" "open" ]; }
        { mime = "text/*"; use = [ "edit" ]; }
        { mime = "application/json"; use = [ "edit" ]; }
        { mime = "application/x-shellscript"; use = [ "edit" ]; }
        { name = "*"; use = [ "open" ]; }
      ];
    };

    keymap = {
      mgr.prepend_keymap = [
        { on = [ "<C-s>" ]; run = "shell --interactive --block"; desc = "Open shell here"; }
        { on = [ "g" "h" ];  run = "cd ~"; desc = "Go to home"; }
        { on = [ "g" "c" ];  run = "cd ~/.config"; desc = "Go to ~/.config"; }
        { on = [ "g" "d" ];  run = "cd ~/dev"; desc = "Go to ~/dev"; }
        { on = [ "g" "n" ];  run = "cd ~/nix_migrate"; desc = "Go to nix config"; }
        # 拷贝当前路径到剪贴板
        { on = [ "y" "p" ]; run = "shell -- 'echo \"$1\" | wl-copy' \"$0\""; desc = "Copy path to clipboard"; }
      ];
    };

    plugins = {
      inherit (pkgs.yaziPlugins) git smart-enter full-border;
    };

    initLua = ''
      require("git"):setup()
      require("full-border"):setup()
    '';
  };
}
