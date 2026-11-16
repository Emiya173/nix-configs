{
  config,
  pkgs,
  lib,
  ...
}:
let
  daemon = lib.getExe config.services.dae.package;
  runtimeConfig = "/run/dae/config.dae";
  # Match the NAT bridge declared in hosts/arch-pc/win11-network.xml. The bridge
  # may appear after DAE starts; DAE's interface manager binds it dynamically.
  lanInterfaces = [ "virbr0" ];
  prepareConfig = lib.escapeShellArgs (
    [
      "${pkgs.python3}/bin/python3"
      "${../../scripts/prepare-dae-config.py}"
      "--output"
      runtimeConfig
    ]
    ++ lib.concatMap (interface: [
      "--lan-interface"
      interface
    ]) lanInterfaces
  );
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
      RuntimeDirectoryMode = "0700";
      ExecReload = "${daemon} reload";
      ExecStart = lib.mkForce [
        ""
        "${daemon} run --disable-timestamp -c ${runtimeConfig}"
      ];
      ExecStartPre = lib.mkForce [
        ""
        "${prepareConfig} --source \${CREDENTIALS_DIRECTORY}/config.dae"
        "${daemon} validate -c ${runtimeConfig}"
      ];
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce 10;
      TimeoutStartSec = 120;
    };
  };
}
