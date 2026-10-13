{
  lib,
  haskellPackages,
  zlib,
  zstd,
  openssl,
  symlinkJoin,
}:
let
  compiled = haskellPackages.callPackage ./build.nix {
    libzstd = zstd;
    inherit openssl;
  };
in
symlinkJoin {
  name = "xlog-0.1.0.0";
  paths = [ compiled ];
  postBuild = "ln -s xlog-hs $out/bin/xlog";
  meta = {
    mainProgram = "xlog";
    platforms = lib.platforms.linux;
  };
}
