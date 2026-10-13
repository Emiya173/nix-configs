{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
}:
stdenvNoCC.mkDerivation {
  pname = "dae-subscription";
  version = "1.0.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    install -Dm644 subscription.py $out/lib/dae-subscription.py
    makeWrapper ${python3}/bin/python3 $out/bin/dae-subscription \
      --add-flags "$out/lib/dae-subscription.py"
  '';
  meta = {
    mainProgram = "dae-subscription";
    platforms = lib.platforms.linux;
  };
}
