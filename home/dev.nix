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

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    # 沿用现有 ~/.config/nvim 配置 (lazyvim/lvim).
    # 不在这里写 plugins,让 lazy.nvim/Lazyman 自管理
  };
}
