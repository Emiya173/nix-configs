{
  config,
  pkgs,
  lib,
  userName,
  ...
}:
let
  user = config.hjem.users.${userName};
  moegirlMinWeight = 10000;
  # 上游萌娘词条没有词频列，默认零权重会沉底；补足最低词频并保留更高权重。
  moegirlDictionary = pkgs.runCommand "moegirl.dict.yaml" { } ''
    ${pkgs.gawk}/bin/awk -v min_weight=${toString moegirlMinWeight} '
      BEGIN { FS = OFS = "\t" }
      /^\.\.\.$/ { entries = 1; print; next }
      entries && NF >= 2 && $0 !~ /^#/ {
        if (NF < 3 || $3 + 0 < min_weight) $3 = min_weight
      }
      { print }
    ' ${pkgs.rime-moegirl}/share/rime-data/moegirl.dict.yaml > "$out"
  '';
  # 在上游词表头追加导入，保留雾凇自带词条和 rime_ice 用户词库名称。
  rimeDictionary = pkgs.runCommand "rime_ice.dict.yaml" { } ''
    ${pkgs.gnused}/bin/sed '/^\.\.\.$/i\  - moegirl' \
      ${pkgs.rime-ice}/share/rime-data/rime_ice.dict.yaml > "$out"
  '';
  managedFiles = [
    user.xdg.config.files."fcitx5/profile"
    user.xdg.data.files."fcitx5/rime/default.custom.yaml"
    user.xdg.data.files."fcitx5/rime/double_pinyin_flypy.custom.yaml"
    user.xdg.data.files."fcitx5/rime/rime_ice.dict.yaml"
    user.xdg.data.files."fcitx5/rime/moegirl.dict.yaml"
  ];
  handoverManifest = pkgs.writeText "fcitx5-managed-files.json" (
    builtins.toJSON (map (file: { inherit (file) source target; }) managedFiles)
  );
in
{
  hjem.users.${userName} = {
    # Fcitx5 优先读取用户 profile；原生模块的 /etc/xdg 默认值不足以覆盖旧选择。
    xdg.config.files."fcitx5/profile" = {
      source = config.environment.etc."xdg/fcitx5/profile".source;
      clobber = true;
    };
    xdg.data.files = {
      "fcitx5/rime/default.custom.yaml".text = ''
        patch:
          schema_list:
            - schema: double_pinyin_flypy
      '';
      # 保留雾凇的完整开关列表；第 0 项为中西文，第 2 项为简繁转换。
      "fcitx5/rime/double_pinyin_flypy.custom.yaml".text = ''
        patch:
          "switches/@0/reset": 0
          "switches/@2/reset": 0
      '';
      # 用户目录中的同名旧词库会遮蔽共享数据，因此也由 Hjem 固定到锁定版本。
      "fcitx5/rime/rime_ice.dict.yaml".source = rimeDictionary;
      # switch 不替换正在运行的 Fcitx5；旧进程的共享目录没有新增的萌娘词库。
      "fcitx5/rime/moegirl.dict.yaml".source = moegirlDictionary;
    };
  };

  # 在现有 HM 交接之后、Hjem 链接之前保留冲突文件；不接管学习数据和编译缓存。
  systemd.services."hjem-migrate-${userName}".script = lib.mkAfter ''
    ${lib.getExe pkgs.python3} ${../../scripts/migrate-fcitx5.py} \
      --manifest ${handoverManifest} \
      --state-dir ${lib.escapeShellArg "${user.xdg.state.directory}/fcitx5"}
  '';

  # 每次 Hjem 激活后同步当前会话；无桌面会话时由 Fcitx5 下次启动自行部署。
  systemd.services."reload-fcitx5-${userName}" = {
    description = "Reload declarative Fcitx5 and Rime configuration for ${userName}";
    wantedBy = [ "hjem.target" ];
    before = [ "hjem.target" ];
    after = [ "hjem-activate@${userName}.service" ];
    requires = [ "hjem-activate@${userName}.service" ];
    unitConfig.RequiresMountsFor = [ user.directory ];
    serviceConfig = {
      User = userName;
      Type = "oneshot";
    };
    script = ''
      export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
      if [ -S "$XDG_RUNTIME_DIR/bus" ] && \
         ${pkgs.systemd}/bin/busctl --user --quiet status org.fcitx.Fcitx5 >/dev/null 2>&1; then
        ${pkgs.systemd}/bin/busctl --user call org.fcitx.Fcitx5 /controller \
          org.fcitx.Fcitx.Controller1 ReloadConfig
        ${pkgs.systemd}/bin/busctl --user call org.fcitx.Fcitx5 /controller \
          org.fcitx.Fcitx.Controller1 SetConfig sv \
          fcitx://config/addon/rime/deploy 'a{sv}' 0
      fi
    '';
  };
}
