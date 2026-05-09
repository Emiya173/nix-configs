{ config, pkgs, lib, ... }:

{
  # btrbk: 声明式 btrfs 快照 + (可选) 异机备份
  # 快照写到 /snapshots/<source>/  下,文件名带时间戳
  # systemd timer 自动跑,不用 cron
  services.btrbk = {
    instances.local = {
      onCalendar = "hourly";          # 触发频率 (实际是否生成由 snapshot_preserve 决定)
      settings = {
        timestamp_format = "long";

        # 保留策略: 24 小时 + 7 天 + 4 周 (不留月度)
        # 语法: "<hourly> <daily> <weekly> <monthly>"
        snapshot_preserve = "24h 7d 4w";
        snapshot_preserve_min = "2h";

        # btrbk 的 volume 必须指向 btrfs root subvol (id=5) 的挂载点 ——
        # 因为它字面去 <volume>/<subvolume> 找子卷; / 已经是 @ 的内容,
        # 里面没有 @ 这个名字,所以 readlink /@ 会失败。
        # /btrfs 这个挂载点在 hardware-configuration.nix 里挂 subvolid=5
        volume."/btrfs" = {
          snapshot_dir = "@snapshots";   # = /btrfs/@snapshots,即 /snapshots subvol
          subvolume = {
            "@home" = { snapshot_create = "always"; };
            "@"     = { snapshot_create = "onchange"; snapshot_preserve = "12h 3d"; };
            # @nix 故意不快照
          };
        };
      };
    };
  };

  # 给 /snapshots 提供独立挂载点说明
  # 实际 mount 在 hosts/.../hardware-configuration.nix 中

  # 一些便捷 CLI
  environment.systemPackages = with pkgs; [
    btrbk
    compsize           # 看 btrfs 实际压缩比
    btdu               # 类 ncdu,但识别 CoW 共享
  ];

  # 关闭高写入目录的 CoW (重要! 否则 docker/虚拟机镜像碎片飞起)
  # 这些目录在首次创建时会自动继承父目录的 nodatacow 属性
  systemd.tmpfiles.rules = [
    "d /var/lib/docker          0710 root root - -"
    "d /var/lib/libvirt/images  0711 root root - -"
    # +C 标志: 关 CoW
    "h /var/lib/docker          - - - - +C"
    "h /var/lib/libvirt/images  - - - - +C"
  ];

  # 周度 scrub: 检测静默坏块
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [ "/" ];
  };
}
