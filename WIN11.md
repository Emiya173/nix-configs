# Windows 11 虚拟机

`arch-pc` 的 [win11.nix](hosts/arch-pc/win11.nix) 管理完整虚拟硬件、默认 NAT 网络、共享目录和 `win11-vm` 命令。[win11.xml](hosts/arch-pc/win11.xml) 来自现有虚拟机的持久定义，保留 UUID `c57f5e4c-95fe-48e0-adf6-3db16ef61b9a`、网卡 MAC、SATA 系统盘、e1000e 网卡、Q35 10.2、UEFI 固件与 TPM 2.0。CPU 为 host-passthrough，4 个虚拟 CPU、8 GiB 内存，空白磁盘默认 128 GiB。修改资源、路径或标识从 `win11.nix` 的 `vm` 入手，设备布局在 XML 中调整。

## 应用与启动

```bash
cd /home/present/mirgate/nix-configs
nh os switch .
win11-vm status
sudo win11-vm start
```

配置激活与开机时，`win11-vm.service` 注册虚拟机、配置共享内存和 virtiofs；不存在磁盘且没有旧 NVRAM/TPM/虚拟机定义时，才创建稀疏 qcow2 空白磁盘。已有磁盘不覆盖、不格式化、不改变总线；有旧状态却缺失磁盘会报错，要求恢复数据。已有同名虚拟机 UUID 或系统盘路径不同也会报错，避免接管错误的虚拟机。

Windows 虚拟机关闭自动启动，libvirt 不自动恢复上次运行的虚拟机，宿主关机时通过 ACPI 关闭来宾而非保存内存状态。`default` NAT 网络设置为自动启动，配置同步时也会确保它已启动，因此重启宿主后可以直接在 virt-manager 启动 Windows，或使用 `sudo win11-vm start`。网络自动启动仅建立网桥和 NAT/DHCP/DNS 服务，不启动 Windows，也不占用其配置的 8 GiB 内存。定义同步只修改下次启动使用的持久 XML，不热插拔、不停止运行中的 Windows。硬件变更需要 Windows 完全关机再开机，来宾内直接重启或暂停/恢复不生效。

旧配置重启后若报 `network 'default' is not active`，先运行 `sudo virsh -c qemu:///system net-start default`，再在 virt-manager 启动 Windows；随后应用本仓库更新以永久修复。`nh os boot .` 在下次重启生效，`nh os switch .` 则立即应用。

Nix 是虚拟机配置的来源。GUI 修改会被 XML 路径监视器重新同步，长期修改应写入 Nix/XML。服务通过 libvirt 的标准化 XML 进行比较，设置相同不会反复重定义。服务、命令与监视器共用锁，避免同时进行配置和备份恢复。

## 全新机器：恢复已有 Windows

先适配新机器的 NixOS 硬件配置，再导入本模块；要求 x86_64 和 KVM。不能直接复制原工作机的磁盘 UUID、网卡和显示器配置。保留本仓库 lock，确保固定的 Q35 10.2 和固件仍可用；跨 CPU 型号迁移时，host-passthrough 暴露的 CPU 特性会变化，需要在目标机器验证 Windows 和应用。

在旧机器中将 Windows 完全关机，确认不是暂停、休眠保存或 managed save，再执行：

```bash
sudo win11-vm backup /mnt/backup/win11-good
```

目标目录必须尚不存在，备份过程中保持 Windows 关机且不要修改共享目录。命令生成权限为 0700 的独立目录，包含：

- `disk.qcow2`：当前 Windows 磁盘内容，转换时展开外部 backing chain，不依赖旧机器上的基础镜像；不保存历史快照树。
- `nvram.fd`：UEFI 变量。
- `tpm/`：该 UUID 的虚拟 TPM 状态。
- `share/`：宿主机共享文件夹及其元数据。
- `domain.xml`：当时的定义，供审计与排障；恢复时仍以 Nix 声明为准。
- `manifest.json`：虚拟机身份、备份时间及所有文件的 SHA-256 清单。

将整个目录复制到新机器或外置存储，再在新机器激活 NixOS 配置。首次激活自动创建的空白磁盘不会启动，也不妨碍随后恢复。执行：

```bash
sudo win11-vm restore /mnt/backup/win11-good
sudo win11-vm restore /mnt/backup/win11-good --apply
sudo win11-vm start
```

第一条仅校验、预览，不修改目标文件；第二条实际恢复，先检查身份、校验和与磁盘完整性，再准备所有数据。原磁盘、NVRAM、TPM 和共享目录保留为旁边的 `*.before-restore-<时间>-<标识>`；替换或定义失败时尝试恢复原文件。保留路径记录在 `/var/lib/libvirt/nix-win11/last-restore.json`，确认新系统后自行清理；脚本不自动删除旧数据。恢复拒绝运行、暂停、managed-save 或仍有 libvirt 快照元数据的目标虚拟机。

文件替换前还会写入私有的 `restore-in-progress.json` 交接记录。若进程被强制终止或断电，该记录会阻止后续自动同步和启动，避免用不成套的磁盘、NVRAM 与 TPM 启动 Windows。此时先根据记录中的 `target`、`retained` 和 `pending` 核对文件并完成恢复或回退，再移走交接记录；不要直接删除记录并尝试启动。

恢复会保留磁盘、固件状态和虚拟 TPM 的配套关系，Windows 内已经安装的 Office、VirtIO、WinFsp 和设置随磁盘恢复。若启用了 BitLocker，应另外保留恢复密钥；迁移和虚拟硬件变化仍可能要求恢复验证。Windows/Office 的账号登录和授权状态需在新机器确认。

备份本身应保存在独立存储；与虚拟机同盘的一份目录不能覆盖磁盘损坏的场景。脚本不创建自动备份计划，也不自动下载或上传 Windows 数据。

## 全新机器：没有备份，重新安装

应用配置后会出现已定义、未启动的 `win11` 和空白磁盘，无需在 GUI 重新配置硬件。

1. 从 [Microsoft](https://www.microsoft.com/software-download/windows11) 下载 Windows 11 x64 ISO，从 [VirtIO 项目](https://github.com/virtio-win/virtio-win-pkg-scripts#downloads) 下载完整版 Stable ISO。
2. 分别放到 `/var/lib/libvirt/boot/windows11.iso` 与 `/var/lib/libvirt/boot/virtio-win.iso`，文件应可被 `qemu-libvirtd` 读取。例如对实际下载路径执行：

   ```bash
   sudo install -m 0644 /实际路径/Windows.iso /var/lib/libvirt/boot/windows11.iso
   sudo install -m 0644 /实际路径/VirtIO.iso /var/lib/libvirt/boot/virtio-win.iso
   sudo win11-vm start
   ```

3. 在 virt-manager 打开已经注册的 `win11` 控制台，按提示从光盘启动并安装 Windows。为兼容已有系统，声明使用 SATA 系统盘和 e1000e 网卡，首次安装不依赖 VirtIO 存储或网络驱动。
4. Windows 内安装 VirtIO Guest Tools、[SPICE Guest Tools](https://www.spice-space.org/download.html)、[WinFsp Core 和 VirtIO FS 服务](https://virtio-win.github.io/Knowledge-Base/Virtiofs:-Shared-file-system.html#guest)，随后安装并登录 Office。
5. 验证中文输入、缩放、剪贴板和共享盘，完全关机后制作第一份备份。

未找到 ISO 时对应光驱保持空盘，不阻止从已有 Windows 磁盘启动；`start` 会根据实际存在的 ISO 更新下次启动配置。安装介质、来宾系统数据、密钥与 Office 不进入 Git 或 Nix store。

## 共享与存储

虚拟机通过 `default` NAT 网络的 `virbr0` 联网。宿主机 WAN 接管不能代替 LAN 转发接管；工作机 [DAE 模块](modules/workstation/dae.nix) 在每次启动时从私有 credential 生成 `/run/dae/config.dae`，保留原有 LAN 接口并加入 `virbr0`。运行目录为 0700，配置为 0600，节点、订阅和既有分流规则不进入 Nix store。配置 reload 继续读取这一运行时配置；DAE 会动态绑定网桥，不依赖 DAE 与 libvirt 的启动先后顺序，也不需要让 Windows 开机自启。

应用配置后，在 Windows 关闭系统/浏览器中重复设置的显式代理，使用虚拟网卡 DHCP 提供的地址、网关和 DNS，再新建连接验证。这里沿用原来的域名/IP 分流规则，并非强制所有目标都走代理；不要把 DAE 的 TProxy 端口 12345 当作 HTTP/SOCKS 代理填写。绑定日志可通过 `journalctl -u dae.service --grep='Bind.*LAN|virbr0'` 查看，使用日志确认接管，不应仅凭 `tc filter` 的空输出判断，因为 DAE 也可能使用 TCX。

共享目录 `/srv/vm-share` 和默认 ACL 由 tmpfiles 管理，挂载标识为 `hostshare`。Windows 安装驱动及服务后，通常显示为 `Z:`。这些来宾组件在 Windows 中安装一次，随后随磁盘备份恢复。

`/var/lib/libvirt/images` 为新文件设置 NOCOW，已有文件不自动转换。NOCOW 减少反复覆写的开销，同时关闭镜像文件的 Btrfs 数据校验和与压缩；目录仍在根子卷内，根快照仍会包含它，修改与快照共享的数据块时仍有 CoW。需要避免根快照影响时，另行迁移到独立子卷并单独备份。

状态与排障：

```bash
win11-vm status
systemctl status win11-vm.service win11-vm.path
journalctl -u win11-vm.service -u win11-vm-refresh.service
sudo win11-vm reconcile
```

仓库验证只执行 `./scripts/check.sh` 和临时目录内的自动化测试；本次实现不激活系统、不关闭现有 Windows、不执行真实数据备份或恢复。
