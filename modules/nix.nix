{ config, pkgs, lib, inputs, ... }:

{
  # nh: NH_FLAKE 全局生效 (nos/nob 不用再带路径),clean 定时器替代 nix.gc
  programs.nh = {
    enable = true;
    flake = "/home/present/nix_migrate";
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 14d";
    };
  };

  nix = {
    # nsh/nrun 的 nixpkgs# 和 nrepl 的 <nixpkgs> 都钉到本 flake 锁定的 stable,
    # 不再去解析全局 registry 的最新 unstable (慢 + 和系统版本不一致)
    registry.nixpkgs.flake = inputs.nixpkgs;
    nixPath = [ "nixpkgs=flake:nixpkgs" ];

    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" "@wheel" ];
      substituters = [
        "https://mirrors.ustc.edu.cn/nix-channels/store"
        "https://cache.nixos.org"
        # priority=50 (cache.nixos.org 默认 40) -> 前面 miss 才查 cachix,
        # 大部分包不会触发 cachix 查询 -> 不卡 nix-daemon
        "https://nix-community.cachix.org?priority=50"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      # 国内访问 cachix 偶尔抽风 —— 5s 连不上就放弃,
      # nix-daemon 不会无限阻塞在 getaddrinfo (上次 daemon disconnect 的根因)
      connect-timeout = 5;
      # 单次 download 不重试,失败快速 fallback 到下一个 substituter
      download-attempts = 1;
    };
    # gc 由上面 programs.nh.clean 定时器负责 (nh 按 generation 数+时间双条件保留)
  };

  nixpkgs.config.allowUnfree = true;

  # 基于 channel 的实现,flake 系统上数据库是空的,只会误报"找不到命令"
  programs.command-not-found.enable = false;

  documentation.nixos.enable = false;
}
