{ lib, pkgs, ... }:

let
  # 静态版与迁移前的 CJK Regular 字形一致，避免可变字体改变终端观感。
  notoSansCJK = pkgs.noto-fonts-cjk-sans.override { static = true; };
  pinnedMonospace = [
    {
      family = "FiraCode Nerd Font Mono";
      directory = "${pkgs.nerd-fonts.fira-code}/share/fonts/truetype/NerdFonts/FiraCode";
      files = map (weight: "FiraCodeNerdFontMono-${weight}.ttf") [
        "Light"
        "Regular"
        "Retina"
        "Medium"
        "SemiBold"
        "Bold"
      ];
    }
    {
      family = "Noto Sans Mono CJK SC";
      directory = "${notoSansCJK}/share/fonts/opentype/noto-cjk";
      # 静态 TTC 中只有 Regular/Bold 提供 Mono 字族。
      files = [
        "NotoSansCJK-Regular.ttc"
        "NotoSansCJK-Bold.ttc"
      ];
    }
  ];
in
{
  fonts = {
    enableDefaultPackages = true;

    packages = with pkgs; [
      harmonyos-sans
      noto-fonts
      notoSansCJK
      noto-fonts-cjk-serif
      noto-fonts-color-emoji # 原 noto-fonts-emoji
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
      # 按文件来源放行锁定包，拒绝同名字族的本地副本；不删除用户字体。
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          ${lib.concatMapStrings (font: "<dir>${font.directory}</dir>") pinnedMonospace}
          <selectfont>
            <acceptfont>
              ${lib.concatMapStrings (
                font:
                lib.concatMapStrings (file: ''
                  <pattern>
                    <patelt name="family"><string>${font.family}</string></patelt>
                    <patelt name="file"><string>${font.directory}/${file}</string></patelt>
                  </pattern>
                '') font.files
              ) pinnedMonospace}
            </acceptfont>
            <rejectfont>
              ${lib.concatMapStrings (font: ''
                <pattern><patelt name="family"><string>${font.family}</string></patelt></pattern>
              '') pinnedMonospace}
            </rejectfont>
          </selectfont>
          <alias binding="strong">
            <family>FiraCode Nerd Font Mono</family>
            <accept><family>Noto Sans Mono CJK SC</family></accept>
          </alias>
        </fontconfig>
      '';

      defaultFonts = {
        serif = [
          "Noto Serif CJK SC"
          "Noto Serif"
        ];
        sansSerif = [
          "HarmonyOS Sans SC"
          "Noto Sans CJK SC"
          "Noto Sans"
        ];
        monospace = [
          "FiraCode Nerd Font Mono"
          "Noto Sans Mono CJK SC"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
}
