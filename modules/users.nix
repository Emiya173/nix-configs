{ config, pkgs, userName, ... }:

{
  users.users.${userName} = {
    isNormalUser = true;
    description = "present";
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "input"
      "docker"
      "render"
      "kvm"
      "libvirtd"
      "plugdev"
    ];
  };

  programs.fish.enable = true;

  security.sudo.wheelNeedsPassword = true;
}
