{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # CLI 基础工具
    # bat/eza/btop/fastfetch 走 programs.* (home/shell.nix);
    # tree/curl/wget/zip/unzip/p7zip 由 system 提供 (modules/packages.nix)
    fd
    ripgrep
    ripgrep-all
    dust # 原 du-dust,nixpkgs 改名了
    duf
    jq
    yq-go
    sd
    tealdeer
    ouch
    tokei
    hyperfine
    parallel
    asciinema
    httpie
    nmap
    iperf3
    socat

    # 远程 / 网络
    rustdesk-flutter # nixpkgs 中是 rustdesk-flutter,旧 rustdesk 已停更
    scrcpy
    wlvncc          # wayland 原生 VNC 客户端
    openssh
    sshfs
    rsync

    # mitmproxy 等
    mitmproxy

    # nix 周边 (nh 由 system 的 programs.nh 提供)
    nix-tree
    nix-output-monitor
    nvd

    claude-code
  ];
}
