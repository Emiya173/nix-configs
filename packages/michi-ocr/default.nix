{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  linkFarm,
  callPackage,
  python312,
  uv,
  autoPatchelfHook,
  makeWrapper,
  gtk3,
  gtk-layer-shell,
  gobject-introspection,
  wrapGAppsHook3,
  glib,
  libGL,
  zlib,
  zstd,
  numactl,
  elfutils,
  grim,
  slurp,
  mpv,
  ffmpeg,
  curl,
  bash,
  src,
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./wheels.json);
  inherit (manifest) wheels;
  wheelhouse = linkFarm "michi-ocr-wheels" (
    map (wheel: {
      inherit (wheel) name;
      path = fetchurl {
        inherit (wheel) name url;
        sha256 = lib.removePrefix "sha256:" wheel.hash;
      };
    }) wheels
  );
  models = callPackage ./models.nix { };
  python = python312.withPackages (ps: [
    ps.pygobject3
    ps.pycairo
  ]);
  runtimeLibraries = [
    stdenv.cc.cc.lib
    zlib
    zstd
    numactl
    elfutils
    glib
    libGL
  ];
  runtimePath = lib.makeBinPath [
    grim
    slurp
    mpv
    ffmpeg
    curl
  ];
in
assert lib.assertMsg (
  builtins.hashFile "sha256" "${src}/uv.lock" == manifest.lockHash
) "michi-ocr uv.lock changed: regenerate packages/michi-ocr/wheels.json";
stdenvNoCC.mkDerivation {
  pname = "michi-ocr-surya";
  version = "0.2.0";
  inherit src;

  nativeBuildInputs = [
    uv
    autoPatchelfHook
    makeWrapper
    gobject-introspection
    wrapGAppsHook3
  ];
  buildInputs = runtimeLibraries ++ [
    gtk3
    gtk-layer-shell
  ];
  dontBuild = true;
  dontWrapGApps = true;
  # The wheel already ships compiled ROCm kernels; stripping them is unnecessary.
  dontStrip = true;
  # autoPatchelfHook handles host ELF dependencies; avoid the generic pass over
  # thousands of GPU code objects shipped in the ROCm wheel.
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/python3.12/site-packages $out/bin
    export UV_CACHE_DIR=$TMPDIR/uv-cache
    uv pip install --offline --no-index --no-deps --no-compile-bytecode \
      --python ${python312}/bin/python3.12 \
      --target $out/lib/python3.12/site-packages ${wheelhouse}/*.whl
    # uv records the local wheelhouse in installation metadata. Its provenance
    # is already locked in wheels.json; keep build inputs out of the runtime closure.
    rm $out/lib/python3.12/site-packages/*.dist-info/direct_url.json
    # The wheel's functorch extension requests this SONAME, but the bundled
    # rocBLAS library is shipped only under its unversioned filename.
    ln -s librocblas.so $out/lib/python3.12/site-packages/torch/lib/librocblas.so.4
    cp -r michi_ocr $out/lib/python3.12/site-packages/
    install -m755 scripts/michi-ocr.sh $out/bin/michi-ocr-trigger
    substituteInPlace $out/bin/michi-ocr-trigger \
      --replace-fail '#!/usr/bin/env bash' '#!${bash}/bin/bash'
    wrapProgram $out/bin/michi-ocr-trigger --prefix PATH : ${runtimePath}
    runHook postInstall
  '';

  postFixup = ''
    for command in michi-ocr michi-ocr-python; do
      args=()
      if [ "$command" = michi-ocr ]; then
        args+=(--add-flags '-m michi_ocr')
      fi
      makeWrapper ${python}/bin/python3.12 $out/bin/$command \
        "''${args[@]}" "''${gappsWrapperArgs[@]}" \
        --set PYTHONPATH "$out/lib/python3.12/site-packages" \
        --set PYTHONNOUSERSITE 1 \
        --set PYTHONSAFEPATH 1 \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibraries} \
        --prefix PATH : ${runtimePath} \
        --set DETECTOR_MODEL_CHECKPOINT ${models.detection} \
        --set FOUNDATION_MODEL_CHECKPOINT ${models.recognition} \
        --set HF_HUB_OFFLINE 1 \
        --set TRANSFORMERS_OFFLINE 1
    done
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/michi-ocr-python ${./smoke-test.py}
    runHook postInstallCheck
  '';

  passthru = { inherit models wheelhouse; };
  disallowedReferences = [ wheelhouse ];
  meta = {
    description = "Wayland OCR with locked Surya models and ROCm dependencies";
    mainProgram = "michi-ocr";
    platforms = [ "x86_64-linux" ];
  };
}
