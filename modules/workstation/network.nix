{
  pkgs,
  lib,
  userName,
  ...
}:
let
  docker = "${pkgs.docker}/bin/docker --host unix:///var/run/docker.sock";
  dnsInit = pkgs.writeShellApplication {
    name = "easyconnect-init-dns";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      for ((attempt = 0; attempt < 60; attempt++)); do
        if ${docker} inspect -f '{{.State.Running}}' easyconnect 2>/dev/null | grep -q true; then
          ${docker} exec easyconnect sh -c 'command -v socat >/dev/null || (apt-get update && apt-get install -y socat)'
          # Compose starts a fresh container on restore. Avoid duplicate forwards
          # when this oneshot is retried against an already running container.
          if ! ${docker} exec easyconnect sh -c 'pgrep -f "[s]ocat UDP4-LISTEN:5353" >/dev/null'; then
            ${docker} exec -d easyconnect socat UDP4-LISTEN:5353,fork,reuseaddr UDP4:127.0.0.1:53
          fi
          exit 0
        fi
        sleep 1
      done
      echo 'EasyConnect container did not become ready' >&2
      exit 1
    '';
  };
in
{
  imports = [ ./dae.nix ];
  systemd.services.easyconnect = {
    description = "Work EasyConnect VPN and internal DNS";
    wantedBy = [ "multi-user.target" ];
    requires = [ "docker.service" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/home/${userName}/container/easyconnect";
      ExecStart = "${docker} compose up -d";
      ExecStartPost = lib.getExe dnsInit;
      ExecStop = "${docker} compose down";
      TimeoutStartSec = 180;
      Restart = "on-failure";
      RestartSec = 30;
    };
  };
  systemd.services.hysteria-client = {
    description = "Work Hysteria client";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      ExecStartPre = "${pkgs.iproute2}/bin/ip route replace 45.194.21.135 via 192.168.11.254 dev enp1s0 mtu 1500";
      ExecStart = "${lib.getExe pkgs.unstable.hysteria} client -c /etc/hysteria/client.yaml";
      Restart = "on-failure";
      RestartSec = 5;
      LimitNOFILE = 65536;
    };
  };
  systemd.services.hysteria-reverse-tunnel = {
    description = "Reverse SSH over Hysteria";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "hysteria-client.service"
    ];
    after = [
      "network-online.target"
      "hysteria-client.service"
    ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      ExecStart = "${pkgs.openssh}/bin/ssh -NT -p 10022 -i /etc/hysteria/vps-reverse.key -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/hysteria/known_hosts -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=3 -o ServerAliveCountMax=2 -R 127.0.0.1:15023:127.0.0.1:22 hytunnel@127.0.0.1";
      Restart = "always";
      RestartSec = 5;
    };
  };
  # Persistent NM profiles and keyring state are restored privately. Never copy
  # /run/NetworkManager profiles (old wg0, Docker bridges and loopback).
  environment.systemPackages = [
    pkgs.docker-compose
    pkgs.unstable.hysteria
  ];
}
