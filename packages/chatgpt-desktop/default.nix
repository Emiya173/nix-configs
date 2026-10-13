{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  buildFHSEnv,
  writeShellScript,
}:
let
  version = "26.1002.52244";
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "chatgpt-desktop-unwrapped";
    inherit version;
    src = fetchurl {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb";
      sha256 = "9498e417131a278bce35bfff6275d252c0d332f17afc0313e0b782749f4d348a";
    };
    nativeBuildInputs = [ dpkg ];
    unpackPhase = ''dpkg-deb --fsys-tarfile "$src" | tar --extract --no-same-permissions'';
    dontBuild = true;
    dontConfigure = true;
    dontFixup = true;
    installPhase = ''
      mkdir -p $out
      cp -r usr $out/
    '';
  };
in
buildFHSEnv {
  pname = "chatgpt-desktop";
  inherit version;
  targetPkgs =
    p: with p; [
      alsa-lib
      at-spi2-core
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      gtk3
      gtk4
      libdrm
      libgbm
      libglvnd
      libnotify
      libpulseaudio
      libsecret
      libusb1
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxkbcommon
      libxrandr
      libxscrnsaver
      mesa
      nspr
      nss
      openssl
      pango
      systemd
      tpm2-tss
      stdenv.cc.cc.lib
      xdg-utils
      git
      bash
      coreutils
      ripgrep
      bubblewrap
    ];
  multiPkgs = null;
  includeClosures = true;
  extraBuildCommands = ''
    # /usr/lib and /lib resolve to /usr/lib64 inside the generated FHS root.
    mkdir -p $out/usr/lib64
    ln -s ${unwrapped}/usr/lib/chatgpt $out/usr/lib64/chatgpt
  '';
  runScript = writeShellScript "chatgpt-desktop-launch" ''
    set -euo pipefail
    flags=(--disable-setuid-sandbox --ozone-platform-hint=auto --enable-wayland-ime --wayland-text-input-version=3)
    flags_file="''${XDG_CONFIG_HOME:-$HOME/.config}/chatgpt-flags.conf"
    if [ -r "$flags_file" ]; then
      while IFS= read -r flag || [ -n "$flag" ]; do
        flag="''${flag%$'\r'}"
        flag="''${flag#"''${flag%%[![:space:]]*}"}"
        flag="''${flag%"''${flag##*[![:space:]]}"}"
        case "$flag" in ""|\#*) continue ;; esac
        flags+=("$flag")
      done < "$flags_file"
    fi
    exec /usr/lib/chatgpt/ChatGPT "''${flags[@]}" "$@"
  '';
  extraInstallCommands = ''
    cp -r ${unwrapped}/usr/share $out/share
    chmod -R u+w $out/share/applications
    substituteInPlace $out/share/applications/chatgpt.desktop \
      --replace-fail "Exec=chatgpt" "Exec=$out/bin/chatgpt-desktop"
    ln -s chatgpt-desktop $out/bin/chatgpt
    cat > $out/bin/codex-desktop <<EOF
    #!/bin/sh
    exec $out/bin/chatgpt-desktop codex:// "\$@"
    EOF
    chmod +x $out/bin/codex-desktop
  '';
  passthru = { inherit unwrapped; };
  meta = {
    mainProgram = "chatgpt-desktop";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.unfree;
  };
}
