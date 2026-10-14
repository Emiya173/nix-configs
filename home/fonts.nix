{
  config,
  pkgs,
  lib,
  nixosConfig,
  ...
}:

let
  defaults = nixosConfig.fonts.fontconfig.defaultFonts;
  uiFont = builtins.head defaults.sansSerif;
  monoFont = builtins.head defaults.monospace;
  cjkMonoFont = "Noto Sans Mono CJK SC";
  systemFontconfig = pkgs.writeText "system-fontconfig.conf" nixosConfig.fonts.fontconfig.localConf;
  fontconfigPath = "${config.xdg.configHome}/fontconfig/fonts.conf";
  alias = family: fonts: ''
    <alias binding="strong">
      <family>${family}</family>
      <prefer>${lib.concatMapStrings (font: "<family>${font}</family>") fonts}</prefer>
    </alias>
  '';
in
{
  # 迁移遗留的 fonts.conf 会覆盖系统默认值；统一接管，保留原文件备份。
  xdg.configFile."fontconfig/fonts.conf" = {
    force = true;
    text = ''
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
        <dir>${pkgs.harmonyos-sans}/share/fonts/truetype/harmonyos-sans</dir>
        <include>${systemFontconfig}</include>
        ${alias "sans-serif" defaults.sansSerif}
        ${alias "serif" defaults.serif}
        ${alias "monospace" defaults.monospace}
        ${alias "emoji" defaults.emoji}
        ${lib.concatMapStrings (family: alias family [ uiFont ]) [
          "system-ui"
          "ui-sans-serif"
          "Rubik"
          "Google Sans Flex"
        ]}
        ${alias "ui-monospace" defaults.monospace}

        <match target="font">
          <edit name="rgba" mode="assign"><const>none</const></edit>
        </match>
      </fontconfig>
    '';
  };

  gtk.font = {
    name = uiFont;
    size = 11;
    package = pkgs.harmonyos-sans;
  };

  dconf.settings."org/gnome/desktop/interface" = {
    font-name = "${uiFont} 11";
    document-font-name = "${uiFont} 11";
    monospace-font-name = "${monoFont} 11";
  };

  home.activation.backupLegacyFontconfig =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        font_config=${lib.escapeShellArg fontconfigPath}
        if [[ -f "$font_config" && ! -L "$font_config" && ! -e "$font_config.pre-harmony-backup" ]]; then
          run cp -p "$font_config" "$font_config.pre-harmony-backup"
        fi
      '';

  # DMS、Qt 与编辑器配置保持可写，只同步字体字段，保留动态主题和其他偏好。
  home.activation.syncApplicationFonts = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.python3}/bin/python3 ${../scripts/sync-application-fonts.py} \
      --config-home ${lib.escapeShellArg config.xdg.configHome} \
      --ui-font ${lib.escapeShellArg uiFont} \
      --mono-font ${lib.escapeShellArg monoFont} \
      --cjk-mono-font ${lib.escapeShellArg cjkMonoFont}
  '';
}
