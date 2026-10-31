{
  config,
  pkgs,
  lib,
  userName,
  ...
}:
let
  adbScript =
    name:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.android-tools
        pkgs.coreutils
      ];
      # Existing device operations are preserved; shellcheck is handled separately.
      checkPhase = ''bash -n "$target"'';
      text = builtins.readFile ../../packages/work-scripts/${name};
    };
in
{
  users.users.${userName}.packages = with pkgs; [
    wayvnc
    bcompare
    dingtalk
    wemeet
    config.programs.localsend.package
    libarchive
    rename
    android-tools
    (lib.lowPrio jdk11)
    maven
    git-repo
    xlog
    (adbScript "close.sh")
    (adbScript "sync_time.sh")
    (adbScript "modifytime.sh")
  ];
  programs.fish = {
    shellAliases = {
      adbs = "adb shell";
      rn = "${pkgs.rename}/bin/rename";
      tar = "bsdtar";
      pip = "uv pip";
    };
    interactiveShellInit = lib.mkAfter ''
      # Do not inherit Toolbox paths from the reused home's universal variables.
      set --global fish_user_paths (string match --invert --regex '(^|/)JetBrains/Toolbox(/|$)' -- $fish_user_paths)
      set --global --export PATH (string match --invert --regex '(^|/)JetBrains/Toolbox(/|$)' -- $PATH)
      for directory in "$HOME/script" /opt/android-sdk/platform-tools "$HOME/.ghcup/bin"
        if test -d "$directory"
          fish_add_path --append "$directory"
        end
      end
      fish_add_path --prepend "${pkgs.android-tools}/bin"
    '';
  };
  # The reused history database has migrations newer than stable Atuin supports.
  programs.atuin.package = pkgs.unstable.atuin;
  programs.yazi.settings.yazi.opener.xlog = [
    {
      run = ''for file in %s; do xlog -- "$file" || exit; done'';
      desc = "Decode xlog";
      for = "unix";
    }
  ];
  programs.yazi.settings.yazi.open.prepend_rules = [
    {
      url = "*.xlog";
      use = "xlog";
    }
  ];
  # The configuration is tied to this unit rather than a mutable user search path.
  systemd.user.services.wayvnc = {
    description = "wayvnc VNC server";
    documentation = [ "man:wayvnc(1)" ];
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    unitConfig = {
      ConditionUser = userName;
      StartLimitIntervalSec = 0;
    };
    script = ''
      echo 'Waiting for an enabled Niri output before starting WayVNC'
      until ${lib.getExe pkgs.niri} msg --json outputs |
        ${lib.getExe pkgs.jq} -e 'any(.[]; .current_mode != null)' >/dev/null; do
        ${lib.getExe' pkgs.coreutils "sleep"} 5
      done
      exec ${lib.getExe pkgs.wayvnc} --config=${pkgs.writeText "wayvnc.conf" "address=0.0.0.0\nport=5900\n"}
    '';
    serviceConfig = {
      # Losing the last output can make WayVNC exit successfully.
      Restart = "always";
      RestartSec = 3;
    };
  };
  # The login compositor does not start graphical-session.target. Its startup
  # hook imports its own sockets and starts this unit in the greeter's manager.
  systemd.user.services.wayvnc-greeter = {
    description = "wayvnc for the login screen";
    documentation = [ "man:wayvnc(1)" ];
    unitConfig.ConditionUser = config.services.greetd.settings.default_session.user;
    script = ''
      while ${lib.getExe pkgs.niri} msg version >/dev/null 2>&1; do
        if ${lib.getExe pkgs.niri} msg --json outputs |
          ${lib.getExe pkgs.jq} -e 'any(.[]; .current_mode != null)' >/dev/null; then
          ${lib.getExe pkgs.wayvnc} --config=${pkgs.writeText "wayvnc-greeter.conf" "address=127.0.0.1\nport=5900\n"} || true
        fi
        ${lib.getExe' pkgs.coreutils "sleep"} 1
      done
    '';
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
  hjem.users.${userName} = {
    # Keep the legacy path used by Yazi and scripts, while building the executable
    # from source. The private key remains in the user's mutable config directory.
    files.".local/bin/xlog".source = "${pkgs.xlog}/bin/xlog";
    files.".local/share/jdks/jdk11".source = "${pkgs.jdk11}";
    files.".local/share/jdks/jdk21".source = "${pkgs.jdk21}";
    files."script/close.sh".source = "${adbScript "close.sh"}/bin/close.sh";
    files."script/sync_time.sh".source = "${adbScript "sync_time.sh"}/bin/sync_time.sh";
    files."script/modifytime.sh".source = "${adbScript "modifytime.sh"}/bin/modifytime.sh";
    # The existing home contains a Toolbox launcher; mask it when reusing @home.
    xdg.data.files."applications/jetbrains-toolbox.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=JetBrains Toolbox
      Hidden=true
    '';
    xdg.config.files."autostart/jetbrains-toolbox.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=JetBrains Toolbox
      Hidden=true
    '';
    # An empty unit masks the old enabled Arch user service when reusing @home.
    xdg.config.files."systemd/user/ydotool.service".text = "";
  };
}
