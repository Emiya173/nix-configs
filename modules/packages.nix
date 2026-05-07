{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # 基础
    vim
    neovim
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
    btop
    duf
    du-dust
    inetutils
    traceroute

    # 编译/开发基础 (system 级,语言版本由 home-manager 管)
    gcc
    gnumake
    cmake
    pkg-config
    binutils
    gdb

    # 内核相关
    linux-firmware
    cpupower

    # 终端工具
    fastfetch
    neofetch

    # NTFS
    ntfs3g
  ];

  programs.git.enable = true;
}
