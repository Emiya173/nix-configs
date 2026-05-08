{ config, pkgs, ... }:

{
  fonts = {
    enableDefaultPackages = true;

    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji   # 原 noto-fonts-emoji
      # noto-fonts-extra 已并入 noto-fonts
      source-han-sans
      source-han-serif
      source-han-mono
      sarasa-gothic
      wqy_microhei
      wqy_zenhei
      liberation_ttf
      dejavu_fonts
      twitter-color-emoji
      jetbrains-mono
      cascadia-code
      fira-code
      fira-code-symbols
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.symbols-only
      material-icons
      material-design-icons
      font-awesome
    ];

    fontconfig = {
      defaultFonts = {
        serif = [ "Noto Serif CJK SC" "Noto Serif" ];
        sansSerif = [ "Noto Sans CJK SC" "Noto Sans" ];
        monospace = [ "JetBrainsMono Nerd Font" "Sarasa Mono SC" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
}
