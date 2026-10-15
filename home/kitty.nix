{
  config,
  pkgs,
  nixosConfig,
  ...
}:

{
  programs.kitty = {
    enable = true;

    font = {
      name = builtins.head nixosConfig.fonts.fontconfig.defaultFonts.monospace;
      size = 11;
    };

    settings = {
      # 禁用文件监视: kitty 每实例的 __watch_conf__ 约占 25MB,
      # Home Manager 替换 store symlink 曾触发 watcher 累积泄漏。
      # DMS 通过 SIGUSR1 重载主题,手动重载 ctrl+shift+f5 仍可用。
      auto_reload_config = -1;
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

    # DMS 动态生成配色与标签栏;首次生成前用 globinclude 忽略缺失文件。
    extraConfig = ''
      globinclude dank-tabs.conf
      globinclude dank-theme.conf
    '';
  };
}
