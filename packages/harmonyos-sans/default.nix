{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation {
  pname = "harmonyos-sans-sc";
  version = "1.0";

  src = fetchurl {
    url = "https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip";
    hash = "sha256-+wLIbjWM2arY1N+pV+5QI4Hn7i6USZqRM63UMkts5po=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 "HarmonyOS Sans/HarmonyOS_Sans_SC/"*.ttf \
      -t "$out/share/fonts/truetype/harmonyos-sans"
    install -Dm644 "HarmonyOS Sans/HarmonyOS_Sans_SC/LICENSE.txt" \
      "$out/share/licenses/harmonyos-sans-sc/LICENSE.txt"
    runHook postInstall
  '';

  meta = {
    description = "Huawei HarmonyOS Sans SC with Simplified Chinese, Latin and digits";
    homepage = "https://developer.huawei.com/consumer/en/design/resource/";
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
  };
}
