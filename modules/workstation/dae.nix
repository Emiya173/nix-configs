{
  config,
  pkgs,
  lib,
  ...
}:
let
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
  systemd.services.dae = {
    wantedBy = [ "multi-user.target" ];
    after = [
      "docker.service"
      "systemd-sysctl.service"
    ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      Type = "notify";
      RuntimeDirectory = "dae";
      ExecReload = "${daemon} reload";
      ExecStartPre = lib.mkForce [
        ""
        "${daemon} validate -c \${CREDENTIALS_DIRECTORY}/config.dae"
      ];
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce 10;
      TimeoutStartSec = 120;
    };
  };
}
