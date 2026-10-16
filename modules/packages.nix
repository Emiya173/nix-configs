{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Neovim 与 vim 别名由 Nixvim 的 NixOS 模块统一提供。
    git
    curl
    wget
    file
    which
    tree
    unzip
    zip
    p7zip
    rar
    unrar
    bubblewrap

    # 系统/磁盘
    btrfs-progs
    parted
    gptfdisk
    smartmontools
    efibootmgr
    pciutils
    usbutils
    lsof
    psmisc
    # btop/duf/dust 是用户侧工具,归 modules/user/
    inetutils
    traceroute

    # 编译/开发基础 (system 级,语言版本由 modules/user/dev.nix 管)
    gcc
    gnumake
    cmake
    pkg-config
    binutils
    gdb

    # 内核相关 (firmware 走 hardware.enableRedistributableFirmware,cpupower 走 powerManagement.cpuFreqGovernor)

    # fastfetch 由 modules/user/wrappers.nix 配置

    # 音视频转码: ffmpeg-full = 默认 ffmpeg 加上几乎所有可选库 (nvenc/vaapi/svt-av1/
    # libfdk_aac/x265/webp/...),省得遇到某些 codec 再切包。
    ffmpeg-full

    # NTFS
    ntfs3g
  ];

  programs.git.enable = true;
}
