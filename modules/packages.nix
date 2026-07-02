{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # 基础 (neovim 由 home-manager nixvim 接管,system 留 vim 给 root 应急)
    vim
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
    # btop/duf/dust 是用户侧工具,归 home-manager (home/packages.nix + programs.btop)
    inetutils
    traceroute

    # 编译/开发基础 (system 级,语言版本由 home-manager 管)
    gcc
    gnumake
    cmake
    pkg-config
    binutils
    gdb

    # 内核相关 (firmware 走 hardware.enableRedistributableFirmware,cpupower 走 powerManagement.cpuFreqGovernor)

    # fastfetch 归 home-manager (programs.fastfetch, home/shell.nix)

    # 音视频转码: ffmpeg-full = 默认 ffmpeg 加上几乎所有可选库 (nvenc/vaapi/svt-av1/
    # libfdk_aac/x265/webp/...),省得遇到某些 codec 再切包。
    ffmpeg-full

    # NTFS
    ntfs3g
  ];

  programs.git.enable = true;
}
