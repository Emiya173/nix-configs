{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # CLI 基础工具
    fd
    ripgrep
    ripgrep-all
    bat
    eza
    du-dust
    duf
    btop
    tree
    jq
    yq-go
    sd
    tealdeer
    ouch
    fastfetch
    tokei
    hyperfine
    parallel
    asciinema
    httpie
    curl
    wget
    nmap
    iperf3
    socat

    # 文件/归档
    p7zip
    unzip
    zip

    # 远程 / 网络
    rustdesk-flutter   # nixpkgs 中是 rustdesk-flutter,旧 rustdesk 已停更
    scrcpy
    openssh
    sshfs
    rsync

    # mitmproxy 等
    mitmproxy

    # nix 周边
    nix-tree
    nix-output-monitor
    nh
    nvd
  ];
}
