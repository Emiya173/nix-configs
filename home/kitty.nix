{ config, pkgs, ... }:

{
  programs.kitty = {
    enable = true;

    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };

    settings = {
      cursor_shape = "beam";
      cursor_trail = 1;
      window_margin_width = "21.75";
      confirm_os_window_close = 0;
      shell = "fish";
      scrollback_lines = 10000;
      enable_audio_bell = "no";
      copy_on_select = "no";
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
    };

    keybindings = {
      "ctrl+c" = "copy_or_interrupt";
      "page_up" = "scroll_page_up";
      "page_down" = "scroll_page_down";
      "ctrl+plus" = "change_font_size all +1";
      "ctrl+equal" = "change_font_size all +1";
      "ctrl+minus" = "change_font_size all -1";
      "ctrl+0" = "change_font_size all 0";
    };

    # quickshell 生成的主题文件,如果不存在则忽略 (迁移期间可能没有)
    extraConfig = ''
      # 取消下行注释当 quickshell 主题文件存在时
      # include ~/.local/state/quickshell/user/generated/terminal/kitty-theme.conf
    '';
  };
}
