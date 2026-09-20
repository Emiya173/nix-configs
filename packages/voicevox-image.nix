{ dockerTools }:

(dockerTools.pullImage {
  imageName = "voicevox/voicevox_engine";
  imageDigest = "sha256:eb8c7f46a7d01217d1ff2b6f018261faedeceded3cc756b4fbbf371791ad6c90";
  hash = "sha256-vnOiCAIH8ppqp39JqoUpxFHj7aZAMtOHZug1PSdpAGc=";
  os = "linux";
  arch = "amd64";
  # This is just the tag stored in the archive; the registry fetch uses the digest.
  # The service runs by the config ID below, so a mutable local tag cannot redirect it.
  finalImageTag = "latest";
}).overrideAttrs
  {
    passthru.imageId = "sha256:f4bfb5866aec6ea52797f54a52f8cef38b2b05cc157f229e60196e3679b8cb66";
  }
