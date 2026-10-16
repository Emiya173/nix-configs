{
  config,
  pkgs,
  lib,
  userName,
  ...
}:

let
  defaults = config.fonts.fontconfig.defaultFonts;
  uiFont = builtins.head defaults.sansSerif;
  monoFont = builtins.head defaults.monospace;
  cjkMonoFont = "Noto Sans Mono CJK SC";
  systemFontconfig = pkgs.writeText "system-fontconfig.conf" config.fonts.fontconfig.localConf;
  configHome = config.hjem.users.${userName}.xdg.config.directory;
  alias = family: fonts: ''
    <alias binding="strong">
      <family>${family}</family>
      <prefer>${lib.concatMapStrings (font: "<family>${font}</family>") fonts}</prefer>
    </alias>
  '';
in
{
  # 迁移遗留的 fonts.conf 会覆盖系统默认值；统一接管，保留原文件备份。
  hjem.users.${userName}.xdg.config.files."fontconfig/fonts.conf" = {
    clobber = true;
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

  users.users.${userName}.packages = [ pkgs.harmonyos-sans ];

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        font-name = "${uiFont} 11";
        document-font-name = "${uiFont} 11";
        monospace-font-name = "${monoFont} 11";
      };
    }
  ];

  # Hjem's target is restarted on each switch and at boot. Run after its links
  # are ready, as the user, while leaving dynamic themes and app settings writable.
  systemd.services."sync-application-fonts-${userName}" = {
    description = "Synchronize application font preferences for ${userName}";
    wantedBy = [ "hjem.target" ];
    before = [ "hjem.target" ];
    after = [ "hjem-activate@${userName}.service" ];
    requires = [ "hjem-activate@${userName}.service" ];
    unitConfig.RequiresMountsFor = [ config.hjem.users.${userName}.directory ];
    serviceConfig = {
      User = userName;
      Type = "oneshot";
    };
    script = ''
      ${pkgs.python3}/bin/python3 ${../../scripts/sync-application-fonts.py} \
        --config-home ${lib.escapeShellArg configHome} \
        --ui-font ${lib.escapeShellArg uiFont} \
        --mono-font ${lib.escapeShellArg monoFont} \
        --cjk-mono-font ${lib.escapeShellArg cjkMonoFont}
    '';
  };
}
