{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  buildFHSEnv,
  writeShellScript,
  commandLineArgs ? [ ],
}:

let
  version = "8.7.0";
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "baidunetdisk-unwrapped";
    inherit version;

    src = fetchurl {
      url = "https://pkg-ant.baidu.com/issue/netdisk/LinuxGuanjia/${version}/baidunetdisk_${version}_amd64.deb";
      hash = "sha256-7HHCrRFRYJ/Q2LhtlRhMC0V9bbWqGIYeCxX8I8z+Afc=";
    };

    nativeBuildInputs = [ dpkg ];
    unpackPhase = ''
      runHook preUnpack
      dpkg-deb --fsys-tarfile "$src" | tar --extract --no-same-permissions
      runHook postUnpack
    '';
    dontBuild = true;
    dontConfigure = true;
    # The client checks its bundled files during native engine initialization.
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r opt "$out/opt"
      cp -r usr/share "$out/share"
      runHook postInstall
    '';
  };
in
buildFHSEnv {
  pname = "baidunetdisk";
  inherit version;

  targetPkgs =
    pkgs: with pkgs; [
      alsa-lib
      at-spi2-core
      cups
      dbus
      expat
      glib
      gtk3
      gtkmm2
      libdrm
      libgbm
      libglvnd
      libpulseaudio
      libsecret
      libva
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxkbcommon
      libxrandr
      libxt
      libxtst
      nss
      stdenv.cc.cc.lib
      (lib.getLib udev) # Chromium dlopens libudev; no systemd services are needed.
      xdg-utils
    ];
  multiPkgs = null;
  includeClosures = true;

  extraBuildCommands = ''
    mkdir -p "$out/opt"
    ln -s ${unwrapped}/opt/baidunetdisk "$out/opt/baidunetdisk"
  '';

  runScript = writeShellScript "baidunetdisk-launch" ''
    export LD_LIBRARY_PATH="/opt/baidunetdisk:/usr/lib:''${LD_LIBRARY_PATH:-}"
    # libbrowserengine uses XChangeProperty after login and aborts with BadWindow
    # on native Wayland. Use XWayland until the bundled native engine supports it.
    exec /opt/baidunetdisk/baidunetdisk --disable-setuid-sandbox --ozone-platform=x11 ${lib.escapeShellArgs commandLineArgs} "$@"
  '';

  extraInstallCommands = ''
    mkdir -p "$out/share"
    cp -r ${unwrapped}/share/applications ${unwrapped}/share/icons "$out/share/"
    chmod -R u+w "$out/share/applications"
    substituteInPlace "$out/share/applications/baidunetdisk.desktop" \
      --replace-fail "Exec=/opt/baidunetdisk/baidunetdisk --no-sandbox" "Exec=$out/bin/baidunetdisk" \
      --replace-fail "Name=baidunetdisk" "Name=百度网盘"
  '';

  passthru = { inherit unwrapped; };
  meta = {
    description = "Baidu Netdisk desktop client";
    homepage = "https://pan.baidu.com/";
    downloadPage = "https://pan.baidu.com/download";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "baidunetdisk";
  };
}
