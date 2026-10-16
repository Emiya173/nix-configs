{
  pkgs,
  ...
}:

{
  programs.yazi = {
    enable = true;

    # 仅写覆盖项,不重复默认值
    settings.yazi = {
      plugin.prepend_previewers = [
        {
          mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}";
          run = "ouch";
        }
      ];
    };

    settings.keymap = {
      mgr.prepend_keymap = [
        {
          on = [ "C" ];
          run = "plugin ouch tar.zst";
          desc = "Compress with ouch";
        }
      ];
    };

    plugins = {
      inherit (pkgs.yaziPlugins) ouch;
    };
  };

  # NixOS's Yazi module wraps its config but does not provide shell integration.
  programs.fish.interactiveShellInit = ''
    function y
      set -l tmp (mktemp -t "yazi-cwd.XXXXX")
      command yazi $argv --cwd-file="$tmp"
      set -l cwd
      if read cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        builtin cd -- "$cwd"
      end
      rm -f -- "$tmp"
    end
  '';
}
