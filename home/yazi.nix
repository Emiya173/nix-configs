{ config, pkgs, lib, ... }:

{
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    shellWrapperName = "y";   # 与 fish 里 `y` 函数一致

    # 仅写覆盖项,不重复默认值
    settings = {
      plugin.prepend_previewers = [
        {
          mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}";
          run = "ouch";
        }
      ];
    };

    keymap = {
      mgr.prepend_keymap = [
        { on = [ "C" ]; run = "plugin ouch tar.zst"; desc = "Compress with ouch"; }
      ];
    };

    plugins = {
      inherit (pkgs.yaziPlugins) ouch;
    };
  };
}
