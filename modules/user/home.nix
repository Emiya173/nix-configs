{
  config,
  lib,
  pkgs,
  inputs,
  hostPaths,
  userName,
  ...
}:
let
  userDirectories = {
    DESKTOP = "Desktop";
    DOCUMENTS = "Documents";
    DOWNLOAD = "Downloads";
    MUSIC = "Music";
    PICTURES = "Pictures";
    PUBLICSHARE = "Public";
    TEMPLATES = "Templates";
    VIDEOS = "Videos";
  };
in
{
  # Hjem imports Cargo.lock from its src during evaluation. Use the existing
  # flake source so a cold `flake check --no-build` needs no fileset store copy.
  hjem.cli.package = (pkgs.callPackage "${inputs.hjem}/cli/package.nix" { }).overrideAttrs {
    src = "${inputs.hjem}/cli";
  };
  hjem.users.${userName} = {
    enable = true;
    directory = hostPaths.home;
    clobberFiles = false;
    xdg.config.files = {
      "git/config".text = lib.generators.toGitINI {
        user.name = "Emiya173";
        user.email = "cno.101@qq.com";
      };
      # DMS reads this conventional path when displaying keybinds/window rules.
      "niri/config.kdl".text = config.programs.niri.finalConfig;
      "user-dirs.dirs".text =
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: directory: ''XDG_${name}_DIR="$HOME/${directory}"'') userDirectories
        )
        + "\n";
      "user-dirs.conf".text = "enabled=False\n";
    };
  };

  users.users.${userName}.packages = [ pkgs.xdg-user-dirs ];
  environment.sessionVariables = {
    XDG_BIN_HOME = "$HOME/.local/bin";
    XDG_CACHE_HOME = "$HOME/.cache";
    XDG_CONFIG_HOME = "$HOME/.config";
    XDG_DATA_HOME = "$HOME/.local/share";
    XDG_STATE_HOME = "$HOME/.local/state";
  }
  // lib.mapAttrs' (
    name: directory: lib.nameValuePair "XDG_${name}_DIR" "$HOME/${directory}"
  ) userDirectories;

  systemd.services."hjem-activate@${userName}" = {
    overrideStrategy = "asDropin";
    preStart = ''
      umask 077
      font_config=${lib.escapeShellArg "${hostPaths.home}/.config/fontconfig/fonts.conf"}
      if [ -f "$font_config" ] && [ ! -L "$font_config" ] && \
         [ ! -e "$font_config.pre-harmony-backup" ] && [ ! -L "$font_config.pre-harmony-backup" ]; then
        ${pkgs.coreutils}/bin/cp -p -- "$font_config" "$font_config.pre-harmony-backup"
      fi
      ${lib.concatMapStringsSep "\n" (directory: ''
        directory=${lib.escapeShellArg "${hostPaths.home}/${directory}"}
        if [ ! -L "$directory" ]; then
          ${pkgs.coreutils}/bin/mkdir -p -- "$directory"
        fi
      '') (lib.attrValues userDirectories)}
    '';
  };
}
