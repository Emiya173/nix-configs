{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  installShellFiles,
  ncurses,
  versionCheckHook,
  zstd,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "codex";
  version = "0.160.0";

  # Pin the official release independently of nixpkgs' update cadence.
  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${finalAttrs.version}/codex-package-x86_64-unknown-linux-musl.tar.zst";
    hash = "sha256-yYoAA/HIWGdsUvIMk/ODJ2HImeMxxE6hXY4gY0YmpMI=";
  };

  sourceRoot = ".";
  nativeBuildInputs = [
    autoPatchelfHook
    installShellFiles
    zstd
  ];
  buildInputs = [ ncurses ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    # Runtime discovery depends on these directories being adjacent to bin/.
    mkdir -p "$out"
    cp -r bin codex-resources codex-path codex-package.json "$out/"

    installShellCompletion --cmd codex \
      --bash <($out/bin/codex completion bash) \
      --fish <($out/bin/codex completion fish) \
      --zsh <($out/bin/codex completion zsh)

    runHook postInstall
  '';

  # The CLI is static musl; the voice host and zsh need NixOS ELF interpreters.
  preFixup = ''
    addAutoPatchelfSearchPath "$out/codex-resources/voice/lib"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "Lightweight coding agent that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "codex";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
