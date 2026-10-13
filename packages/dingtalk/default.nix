{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  buildFHSEnv,
  writeShellScript,
}:
let
  version = "8.2.8.260904001";
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "dingtalk-unwrapped";
    inherit version;
    src = fetchurl {
      url = "https://dtapp-pub.dingtalk.com/dingtalk-desktop/xc_dingtalk_update/linux_deb/Release/com.alibabainc.dingtalk_${version}_amd64.deb";
      sha512 = "5a1adf50cb7f36443f4b39c436b980fdbbfa50814367f3be8a6a54c67a07cf1dd96c0ecabd08bb60936e46e77d715073ff5f9ec0ce6dc918ba269f8bccd93a2e";
    };
    nativeBuildInputs = [ dpkg ];
    unpackPhase = ''dpkg-deb --fsys-tarfile "$src" | tar --extract --no-same-permissions'';
    dontBuild = true;
    dontConfigure = true;
    dontFixup = true;
    installPhase = ''
      mkdir -p $out/opt/dingtalk/release
      cp -r opt/apps/com.alibabainc.dingtalk/files/*-Release.*/* $out/opt/dingtalk/release/
      cp opt/apps/com.alibabainc.dingtalk/files/version $out/opt/dingtalk/version
      # Use the FHS environment's system libraries rather than old bundled glibc.
      rm -f $out/opt/dingtalk/release/libm.so.6 $out/opt/dingtalk/release/libstdc++* $out/opt/dingtalk/release/libgtk-x11-2.0.so.*
    '';
  };
in
buildFHSEnv {
  pname = "dingtalk";
  inherit version;
  targetPkgs =
    p: with p; [
      alsa-lib
      at-spi2-core
      cairo
      cups
      dbus
      expat
      fontconfig
      freetype
      glib
      gtk2
      gtk3
      libGL
      libGLU
      libgbm
      libdrm
      libxcrypt-legacy
      libpulseaudio
      libsecret
      nss
      nspr
      libx11
      libxcb
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxrandr
      libxrender
      libxscrnsaver
      libxtst
      libxkbcommon
      mesa
      openssl
      pango
      stdenv.cc.cc.lib
      udev
      xdg-utils
      zlib
      zenity
      libsForQt5.qtwayland
      libsForQt5.qtbase
    ];
  multiPkgs = null;
  includeClosures = true;
  extraBuildCommands = ''
    mkdir -p $out/opt
    ln -s ${unwrapped}/opt/dingtalk $out/opt/dingtalk
  '';
  runScript = writeShellScript "dingtalk-launch" ''
    cd /opt/dingtalk/release
    export LD_LIBRARY_PATH="$PWD:''${LD_LIBRARY_PATH:-}"
    export QT_QPA_PLATFORM="wayland;xcb"
    export QT_AUTO_SCREEN_SCALE_FACTOR=1
    exec ./com.alibabainc.dingtalk "$@"
  '';
  extraInstallCommands = ''
    mkdir -p $out/share/applications
    cat > $out/share/applications/com.alibabainc.dingtalk.desktop <<EOF
    [Desktop Entry]
    Name=钉钉
    Type=Application
    Exec=$out/bin/dingtalk %U
    Terminal=false
    Categories=Network;Office;
    EOF
  '';
  meta = {
    mainProgram = "dingtalk";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.unfree;
  };
}
