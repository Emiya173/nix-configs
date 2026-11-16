{
  pkgs,
  lib,
  userName,
  ...
}:
let
  # Identity and disk bus match the existing installation; keep them on restore.
  vm = {
    name = "win11";
    uuid = "c57f5e4c-95fe-48e0-adf6-3db16ef61b9a";
    mac = "52:54:00:55:59:5d";
    machine = "pc-q35-10.2";
    vcpus = 4;
    memoryMiB = 8192;
    diskGiB = 128;
    disk = "/var/lib/libvirt/images/win11.qcow2";
    nvram = "/var/lib/libvirt/qemu/nvram/win11_VARS.fd";
    tpm = "/var/lib/libvirt/swtpm/c57f5e4c-95fe-48e0-adf6-3db16ef61b9a";
    share = "/srv/vm-share";
    network = "default";
    windowsISO = "/var/lib/libvirt/boot/windows11.iso";
    virtioISO = "/var/lib/libvirt/boot/virtio-win.iso";
    state = "/var/lib/libvirt/nix-win11";
    lock = "/run/lock/win11-vm.lock";
    qemuUser = "qemu-libvirtd";
  };
  substitutions = {
    NAME = vm.name;
    UUID = vm.uuid;
    MAC = vm.mac;
    MACHINE = vm.machine;
    VCPUS = toString vm.vcpus;
    MEMORY_KIB = toString (vm.memoryMiB * 1024);
    DISK = vm.disk;
    NVRAM = vm.nvram;
    FIRMWARE_CODE = "/run/libvirt/nix-ovmf/edk2-x86_64-secure-code.fd";
    FIRMWARE_VARS = "/run/libvirt/nix-ovmf/edk2-i386-vars.fd";
    NETWORK = vm.network;
    SHARE = vm.share;
    WINDOWS_ISO = vm.windowsISO;
    VIRTIO_ISO = vm.virtioISO;
  };
  domainXML = pkgs.writeText "win11-domain.xml" (
    lib.replaceStrings (map (name: "@${name}@") (
      builtins.attrNames substitutions
    )) (builtins.attrValues substitutions) (builtins.readFile ./win11.xml)
  );
  settings = pkgs.writeText "win11-vm.json" (
    builtins.toJSON (
      vm
      // {
        domainXML = domainXML;
        networkXML = ./win11-network.xml;
        qemuImg = "${pkgs.qemu_kvm}/bin/qemu-img";
        copy = "${pkgs.coreutils}/bin/cp";
      }
    )
  );
  python = pkgs.python3.withPackages (ps: [ ps.libvirt ]);
  command = pkgs.writeShellApplication {
    name = "win11-vm";
    text = ''
      exec ${python}/bin/python3 ${../../scripts/windows-vm.py} --config ${settings} "$@"
    '';
  };
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${lib.getExe command} reconcile";
    UMask = "0077";
  };
in
{
  programs.virt-manager.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore";
    onShutdown = "shutdown";
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
      vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };
  environment.systemPackages = [ command ];
  system.build.win11-domain = domainXML;
  system.build.win11-settings = settings;
  systemd.tmpfiles.rules = [
    "d /var/lib/libvirt/boot 0755 root root - -"
    # Only new images inherit NOCOW; existing disks are never converted in place.
    "d /var/lib/libvirt/images 0711 root root - -"
    "h /var/lib/libvirt/images - - - - +C"
    "d ${vm.state} 0700 root root - -"
    "d ${vm.share} 2770 ${userName} qemu-libvirtd - -"
    "a+ ${vm.share} - - - - u:${userName}:rwx,u:qemu-libvirtd:rwx,d:u:${userName}:rwx,d:u:qemu-libvirtd:rwx"
  ];
  systemd.services.win11-vm = {
    description = "Define the Windows 11 virtual machine from Nix";
    wantedBy = [ "multi-user.target" ];
    requires = [ "libvirtd.service" ];
    after = [
      "libvirtd.service"
      "systemd-tmpfiles-setup.service"
    ];
    serviceConfig = serviceConfig // {
      RemainAfterExit = true;
    };
  };
  systemd.paths.win11-vm = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "/var/lib/libvirt/qemu/${vm.name}.xml";
      Unit = "win11-vm-refresh.service";
    };
  };
  systemd.services.win11-vm-refresh = {
    description = "Reconcile changes to the Windows 11 definition";
    requires = [ "libvirtd.service" ];
    after = [
      "libvirtd.service"
      "systemd-tmpfiles-setup.service"
    ];
    inherit serviceConfig;
  };
}
