{ config, pkgs, ... }:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      # fcitx5-chinese-addons / configtool 顶层都已迁到 qt6Packages 命名空间
      addons = with pkgs; [
        fcitx5-rime
        qt6Packages.fcitx5-chinese-addons
        fcitx5-gtk
        qt6Packages.fcitx5-configtool
        fcitx5-material-color
        rime-data
      ];
    };
  };

  # rime-ice / 萌娘拼音 词库不在 nixpkgs,需要手动 clone 到
  # ~/.local/share/fcitx5/rime/  (见 README)
}
