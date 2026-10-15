{
  config,
  pkgs,
  lib,
  hostName,
  userName,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/boot.nix
    ../../modules/network.nix
    ../../modules/audio.nix
    ../../modules/desktop.nix
    ../../modules/input-method.nix
    ../../modules/keyd.nix
    ../../modules/fonts.nix
    ../../modules/locale.nix
    ../../modules/services.nix
    ../../modules/users.nix
    ../../modules/packages.nix
    ../../modules/nix.nix
    ../../modules/overlays.nix
    ../../modules/workstation/network.nix
  ];
  networking.hostName = hostName;
  # Sangfor DNS returns empty answers for EDNS requests; keep the Arch resolver
  # behavior on this VPN workstation.
  networking.resolvconf.dnsExtensionMechanism = false;
  # Share a manually started ADB server and scrcpy forwards on the wired LAN.
  networking.firewall.interfaces.enp1s0 = {
    allowedTCPPorts = [ 5037 ];
    allowedTCPPortRanges = [
      {
        from = 27183;
        to = 27199;
      }
    ];
  };
  # Runtime libraries for the existing ghcup bindists retained in @home.
  programs.nix-ld.libraries = with pkgs; [
    ncurses
    gmp
    libffi
    zlib
  ];
  boot.loader.grub.useOSProber = lib.mkForce false;
  users.users.${userName} = {
    uid = 1000;
    group = userName;
    hashedPasswordFile = "/var/lib/nixos-secrets/present-password-hash";
    extraGroups = lib.mkForce [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "input"
      "docker"
      "render"
    ];
  };
  users.groups.${userName}.gid = 1000;
  programs.localsend = {
    enable = true;
    # Reused Arch settings use schema v3; 1.17 expects boolean quick-save values.
    package = pkgs.unstable.localsend;
    openFirewall = true;
  };
  virtualisation = {
    docker.autoPrune.enable = lib.mkForce false;
    waydroid.enable = lib.mkForce false;
  };
  services.sunshine.enable = lib.mkForce false;
  # Same retention policy as the private host, with the NEW root as source.
  services.btrbk.instances.local = {
    onCalendar = "hourly";
    settings = {
      timestamp_format = "long";
      snapshot_preserve = "24h 7d 4w";
      snapshot_preserve_min = "2h";
      volume."/btrfs" = {
        snapshot_dir = "@snapshots";
        subvolume = {
          "@home".snapshot_create = "always";
          "@nixos" = {
            snapshot_create = "onchange";
            snapshot_preserve = "12h 3d";
          };
        };
      };
    };
  };
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [ "/" ];
  };
  services.smartd.enable = true;
  systemd.tmpfiles.rules = [
    "d /opt/android-sdk 0755 root root - -"
    "L+ /opt/android-sdk/platform-tools - - - - ${pkgs.android-tools}/bin"
    "d /var/lib/docker 0710 root root - -"
    "h /var/lib/docker - - - - +C"
  ];
  environment.systemPackages = with pkgs; [
    btrbk
    compsize
    btdu
    libva-utils
    vulkan-tools
  ];
  system.stateVersion = "26.05";
}
