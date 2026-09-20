{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Rust
    rustup # 用 rustup 管理 toolchain,而非 nixpkgs 的 rust
    cargo-watch
    cargo-edit

    # Node (npm 已随 nodejs_22 自带)
    nodejs_22
    pnpm
    yarn

    # JDK
    jdk21
    gradle
    kotlin

    # Python
    (python3.withPackages (
      ps: with ps; [
        pip
        pynvim
        pytesseract
        requests
      ]
    ))
    uv
    poetry

    # 编辑器/IDE
    vscode
    androidStudioPackages.beta # 2026.1+,launcher 默认 -Dawt.toolkit.name=auto → 原生 Wayland
    # jetbrains.idea-community  # 按需放开

    # C/C++:用 clang 作默认工具链(自带 cc/c++/cpp + binutils)
    clang

    # Go
    go

    # Zig
    zig

    # Haskell (NixOS 上 ghcup 动态链接坑多,直接用 nixpkgs 的 GHC + cabal)
    ghc
    cabal-install
    haskell-language-server

    # 工具 (direnv + nix-direnv 由下面 programs.direnv 自动装,这里不重复)
    just
    typst
    mdbook
    xmake
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableFishIntegration = true;
  };

}
