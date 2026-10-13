# Generated from the vendored Cabal manifest; checked in to keep flake evaluation pure.
{
  mkDerivation,
  base,
  binary,
  bytestring,
  directory,
  filepath,
  lib,
  libzstd,
  openssl,
  process,
  text,
  time,
  zlib,
}:
mkDerivation {
  pname = "xlog-hs";
  version = "0.1.0.0";
  src = ./source;
  # Nix invokes Setup directly; Cabal's self build-tool is otherwise absent from
  # PATH when the CLI suite runs.
  preCheck = ''export PATH="$PWD/dist/build/xlog-hs:$PATH"'';
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    base
    binary
    bytestring
  ];
  libraryPkgconfigDepends = [
    libzstd
    openssl
    zlib
  ];
  executableHaskellDepends = [
    base
    binary
    bytestring
    directory
    filepath
    text
  ];
  executablePkgconfigDepends = [
    libzstd
    zlib
  ];
  testHaskellDepends = [
    base
    binary
    bytestring
    directory
    filepath
    process
  ];
  benchmarkHaskellDepends = [
    base
    binary
    bytestring
    directory
    filepath
    process
    text
    time
  ];
  benchmarkPkgconfigDepends = [
    libzstd
    zlib
  ];
  description = "Mars xlog decoder with a functional Haskell core";
  license = lib.meta.getLicenseFromSpdxId "MIT";
}
