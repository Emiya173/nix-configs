{ config, pkgs, ... }:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      # fcitx5-chinese-addons / configtool 顶层都已迁到 qt6Packages 命名空间
      addons = with pkgs; [
        # rime-ice (雾凇拼音) 词库经 rimeDataPkgs 声明式注入,不再手动 clone。
        # rime-ice 排在 rime-data 前: 两者都带 double_pinyin_flypy.schema.yaml,
        # symlinkJoin 先到先得,必须让 rime-ice 的 schema (挂雾凇词库) 生效
        (fcitx5-rime.override { rimeDataPkgs = [ rime-ice rime-data ]; })
        qt6Packages.fcitx5-chinese-addons
        fcitx5-gtk
        qt6Packages.fcitx5-configtool
        fcitx5-material-color
      ];
    };
  };
}
