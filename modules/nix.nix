{ config, pkgs, lib, ... }:

{
  nix = {
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
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  # 临时跳过 openldap test017 (syncrepl 7 秒 sleep,在 busy 系统上 flaky 经常超时);
  # nixos-unstable 某些 commit hydra 也挂同样测试 -> cache.nixos.org 没缓存 ->
  # fetch 不到 -> 本地编又挂同一个测试。upstream 修好后可删
  nixpkgs.overlays = [
    (final: prev: {
      openldap = prev.openldap.overrideAttrs (_: { doCheck = false; });
    })
  ];

  documentation.nixos.enable = false;
}
