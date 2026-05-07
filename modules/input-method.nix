{ config, pkgs, ... }:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [
        fcitx5-rime
        fcitx5-chinese-addons
        fcitx5-gtk
        fcitx5-configtool
        fcitx5-material-color
        rime-data
      ];
    };
  };

  # rime-ice / 萌娘拼音 词库不在 nixpkgs,需要手动 clone 到
  # ~/.local/share/fcitx5/rime/  (见 README)
}
