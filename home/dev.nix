{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Rust
    rustup        # 用 rustup 管理 toolchain,而非 nixpkgs 的 rust
    cargo-watch
    cargo-edit

    # Node
    nodejs_22
    pnpm
    yarn
    nodePackages.npm

    # JDK
    jdk17
    jdk21
    gradle
    kotlin

    # Python
    (python3.withPackages (ps: with ps; [
      pip
      pynvim
      pytesseract
      requests
    ]))
    uv
    poetry

    # 编辑器/IDE
    vscode
    # jetbrains.idea-community  # 按需放开

    # 工具
    direnv
    nix-direnv
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

  # nvim 配置由 home/nvim.nix (nixvim) 接管
}
