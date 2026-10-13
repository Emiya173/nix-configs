{
  config,
  pkgs,
  lib,
  ...
}:
let
  relay = pkgs.callPackage ../../packages/dae-subscription { };
  command = lib.getExe relay;
  daemon = lib.getExe config.services.dae.package;
in
{
  services.dae = {
    enable = true;
    package = pkgs.unstable.dae;
    configFile = "/etc/dae/config.dae";
    # The original config disables automatic firewall rules. Keep the native
    # module's TProxy opening; tproxy_port_protect remains in the private config.
    openFirewall = {
      enable = true;
      port = 12345;
    };
  };
  users.users.dae-subscription = {
    isSystemUser = true;
    group = "dae-subscription";
  };
  users.groups.dae-subscription = { };
  systemd.tmpfiles.rules = [ "d /var/lib/dae-subscription-config 0700 root root - -" ];
  systemd.services.dae-subscription = {
    description = "DAE local subscription relay";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${command} serve";
      User = "dae-subscription";
      Group = "dae-subscription";
      StateDirectory = "dae-subscription";
      StateDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_UNIX"
      ];
    };
  };
  systemd.services.dae-subscription-sync = {
    description = "Refresh and apply the private DAE subscription";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "dae-subscription.service"
    ];
    after = [
      "network-online.target"
      "dae-subscription.service"
    ];
    # A transient failure must remain recoverable without reset-failed.
    startLimitIntervalSec = 0;
    environment.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    serviceConfig = {
      Type = "oneshot";
      User = "dae-subscription";
      Group = "dae-subscription";
      StateDirectory = "dae-subscription";
      StateDirectoryMode = "0700";
      UMask = "0077";
      LoadCredential = [ "upstream-url:/var/lib/dae-subscription-config/upstream-url" ];
      ExecStart = "${command} sync --url-file \${CREDENTIALS_DIRECTORY}/upstream-url";
      # Only this narrow helper has permission to ask DAE to reload.
      ExecStartPost = "+${command} apply --dae ${daemon} --systemctl ${pkgs.systemd}/bin/systemctl";
      TimeoutStartSec = 150;
      Restart = "on-failure";
      RestartSec = 60;
    };
  };
  systemd.timers.dae-subscription-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitInactiveSec = "60s";
      AccuracySec = "5s";
    };
  };
  systemd.paths.dae-subscription-config = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "/var/lib/dae-subscription-config/upstream-url";
      Unit = "dae-subscription-sync.service";
    };
  };
  systemd.services.dae = {
    wantedBy = [ "multi-user.target" ];
    wants = [
      "dae-subscription.service"
      "dae-subscription-sync.service"
    ];
    after = [
      "dae-subscription.service"
      "dae-subscription-sync.service"
      "docker.service"
      "systemd-sysctl.service"
    ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      Type = "notify";
      RuntimeDirectory = "dae";
      ExecReload = "${daemon} reload";
      ExecStartPre = lib.mkAfter [ "${command} ready --timeout 90" ];
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce 10;
      TimeoutStartSec = 120;
    };
  };
}
