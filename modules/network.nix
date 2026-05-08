{ config, pkgs, ... }:

{
  networking = {
    networkmanager.enable = true;
    firewall.enable = true;
  };

  services.tailscale.enable = true;

  programs.ssh.startAgent = true;
  # NixOS 25.11+ 默认开了 gcr-ssh-agent (gnome-keyring 的 ssh 桥),会和 openssh 的 ssh-agent 冲突
  services.gnome.gcr-ssh-agent.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  environment.systemPackages = with pkgs; [
    networkmanagerapplet
    bluez-tools
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;
}
