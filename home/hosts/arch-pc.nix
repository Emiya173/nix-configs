{
  config,
  pkgs,
  lib,
  ...
}:
let
  xlog = pkgs.callPackage ../../packages/xlog { };
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
  home.stateVersion = lib.mkForce "26.05";
  home.packages = with pkgs; [
    bcompare
    (pkgs.callPackage ../../packages/dingtalk { })
    wemeet
    localsend
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
    (pkgs.callPackage ../../packages/chatgpt-desktop { })
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
  # Keep the legacy path used by Yazi and scripts, while building the executable
  # from source. The private key remains in the user's mutable config directory.
  home.file.".local/bin/xlog".source = "${xlog}/bin/xlog";
  home.file.".local/share/jdks/jdk11".source = "${pkgs.jdk11}";
  home.file.".local/share/jdks/jdk21".source = "${pkgs.jdk21}";
  home.file."script/close.sh".source = "${adbScript "close.sh"}/bin/close.sh";
  home.file."script/sync_time.sh".source = "${adbScript "sync_time.sh"}/bin/sync_time.sh";
  home.file."script/modifytime.sh".source = "${adbScript "modifytime.sh"}/bin/modifytime.sh";
  programs.yazi.settings.opener.xlog = [
    {
      run = ''for file in %s; do xlog -- "$file" || exit; done'';
      desc = "Decode xlog";
      for = "unix";
    }
  ];
  programs.yazi.settings.open.prepend_rules = [
    {
      url = "*.xlog";
      use = "xlog";
    }
  ];
  xdg.desktopEntries.codex-desktop = {
    name = "Codex";
    comment = "Open the Codex desktop workspace";
    exec = "codex-desktop %U";
    icon = "chatgpt";
    terminal = false;
    categories = [ "Development" ];
  };
  # The existing home contains a Toolbox launcher; mask it when reusing @home.
  xdg.dataFile."applications/jetbrains-toolbox.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=JetBrains Toolbox
    Hidden=true
  '';
  xdg.configFile."autostart/jetbrains-toolbox.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=JetBrains Toolbox
    Hidden=true
  '';
  # An empty unit masks the old enabled Arch user service when reusing @home.
  xdg.configFile."systemd/user/ydotool.service".text = "";
}
