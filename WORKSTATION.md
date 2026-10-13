# Arch 工作机迁移准备

目标为 `arch-pc`，私人主机为 `present-pc`。桌面、Rime 输入法、DMS greeter 和锁屏来自审计固定的私人基准 `950423b`，保留多主机结构；工作机另外声明网络、应用与本地工具。执行验证不会激活 NixOS。

## 当前实现

- 实体屏 `HDMI-A-1`，2560×1440@74.968、scale1；Intel UHD770、Intel microcode 与 VAAPI。工作机不导入 AMD 或 gaming 模块。
- 工作机禁用 Waydroid/Sunshine，不安装 Wine/VirtualBox、Timeshift、旧 Python 环境和旧 MediaTek/I²C/虚拟摄像头定制。不带 Scratch、投屏/虚拟输出或 Mod+A 入口。
- Fish 保留所选工具链 PATH 与 `adbs`、Perl `rn`、`tar=bsdtar`、`pip=uv pip`。三份 ADB 脚本包装明确的 Bash/ADB/date 依赖，并管理原 `~/script` 入口；首次 Home Manager 激活会备份冲突文件为 `.hm-backup`。
- JDK21 为默认命令，JDK11 以低优先级保留；项目可用 `~/.local/share/jdks/jdk11` 或 `jdk21` 明确选择 `JAVA_HOME`。
- xlog 源码已随仓库保存，依赖 zlib/zstd/OpenSSL3，以 Nix 构建并运行原项目测试，提供 `xlog` 和 `~/.local/bin/xlog`。实际解码密钥仍在 `~/.config/xlog/private.key`，不进仓库或 store。
- 增加 Beyond Compare、钉钉、腾讯会议、LocalSend、百度网盘与当前 Linux ChatGPT 桌面包；同一个桌面客户端包含 Codex 界面，并提供单独 Codex 桌面入口。CLI `codex` 继续独立提供。登录、界面、会议共享须在目标图形环境验收。
- 保留 OBS、ffmpeg-full、mpv、imv/gthumb/Satty/hyprpicker。DMS 已内建剪贴板粘贴，所选脚本/快捷键无 ydotool 调用，不迁移旧 ydotool 服务、用户组或专属配置；keyd 继续提供轻点 Super 启动器。移除 claude-code overlay 入口。Toolbox 应用、专属配置和 scripts PATH 不迁移，复用 home 时屏蔽旧菜单和自启动入口。
- 保留 NetworkManager 持久连接、DAE、EasyConnect、Hysteria/反向 SSH。WireGuard/wstunnel 退役，不迁移。Hysteria 15903/VNC 旧转发默认不恢复，SSH 15023 保留。
- DAE 使用已锁定 `nixpkgs-unstable` 中的包，不单独固定版本。工作配置通过运行时 credential 读取，不将含节点凭据的配置嵌入 Nix。
- EasyConnect 使用原 Compose 工作目录与系统 Docker socket，启动后自动初始化 DNS。恢复前 Docker autoPrune 禁用，避免清掉待用镜像/卷。

## DAE 自动订阅

DAE 配置中的订阅入口保持 `http://127.0.0.1:8080/sub`。

| 单元 | 行为 |
| --- | --- |
| dae-subscription.service | 仅监听 loopback，持续提供磁盘上的有效缓存，无需先联网；不持有上游 URL |
| dae-subscription-sync.service | 每次启动加载私密 URL credential，获取、解码并校验候选节点；成功后自动 reload DAE |
| dae-subscription-sync.timer | 每60秒检查恢复/待应用状态，正常内容获取间隔为1小时；失败自动重试 |
| dae-subscription-config.path | 源文件变化触发同步，原子替换也覆盖；并发变更最终由后续检查收敛 |

DAE 首次启动等待有效缓存，无缓存/断网时自动重试。有缓存时离线可启动；更新失败保留现有内容。候选与已应用状态分开保存，reload 失败还原发布缓存并保留候选重试。进程重启后重新核对应用状态。订阅同步程序不输出完整 URL、节点或原始异常。DAE 自身的日志策略仍来自私密配置。

上游地址只保存在 `/var/lib/dae-subscription-config/upstream-url`，root:root 0600，目录0700。安装准备时输入一次；之后更换这个私密文件即可，无需 rebuild 或手工按顺序启动服务。不要通过命令行参数、shell history 或 Git 保存完整订阅 URL。

缓存位于 `/var/lib/dae-subscription/`，0700/0600。上游请求不继承代理环境，避免首次启动依赖 DAE 的循环。HTTP 健康只说明已有通过语法检查的节点，不证明所有节点远端可达。

## Btrfs 与安装前提

当前配置是计划布局，尚未创建任何子卷或执行安装：

| 挂载点 | 子卷/设备 |
| --- | --- |
| / | @nixos，新建，保留原 Arch @ |
| /home | @home，UID/GID1000 |
| /nix | @nix，新建 |
| /snapshots | @snapshots，新建 |
| /btrfs | Btrfs 顶层 subvolid=5 |
| /boot | 现有 ESP，UUID BC4C-93AB |

Btrfs UUID 为 `98fc4f2c-cd94-4e94-810e-7757fd903ee3`。安装环境必须再次生成并核对硬件配置，确认这些挂载和24GB swap UUID。btrbk 每小时对 @home 和 **@nixos** 快照，home保留24h/7d/4w，根保留12h/3d，最小2h；@nix不快照，weekly scrub、smartd沿用基准。这是同盘快照，独立工作数据备份仍需另做。

内存交换沿用私人基准：zram 优先（zstd、逻辑容量为内存的50%、priority5，按需分配实际内存），现有约24GiB磁盘 swap 仅作额外容量兜底。

在已经挂载正确目标的安装环境中，`scripts/stage-workstation-state.sh /mnt` 可私密导入 DAE/Hysteria、11份 NM profile、SSH host identity 与当前登录密码 hash。脚本拒绝运行根和非 @nixos 挂载，不创建子卷或启停服务；需要 root，未在本轮执行。没有现成订阅源文件时通过终端隐藏输入获取。

`scripts/preflight-workstation.sh /mnt` 只检查所需文件、权限与挂载。还必须完成所选工作数据、源码/密钥、约25.3GiB本地构建镜像、EasyConnect匿名卷的独立备份与恢复检查。导入脚本不会替代这些备份。

密码 hash 运行时路径为 `/var/lib/nixos-secrets/present-password-hash`。必须在首次安装激活前准备，保证本地登录和 sudo 可用。SSH 采用基准的禁用密码/root策略；切换前验证真实客户端公钥登录，原有 userdbctl 授权来源不能默认视为已覆盖。

## 验证命令

2026-10-13 已用本机 Nix 2.35.2 完成：双主机完整求值、工作机系统 closure 构建、xlog 原项目测试与 CLI 测试、钉钉/ChatGPT 桌面包构建，以及订阅服务的 11 项失败恢复与隐私测试。最终求值确认 Toolbox 和所选排除项未安装；旧 Toolbox 菜单/自启动入口被屏蔽，继承的 Fish PATH 也会过滤其目录。

本机审计目录 `../arch/` 保存验证记录 `implementation-verification.json` 与有效配置 `workstation-effective.json`，这些材料独立于本 Git 仓库。这些验证没有执行目标系统激活、真实订阅获取、工作网络请求或图形应用登录；后几项仍需在安装后的实际环境验收。

在仓库执行：

```sh
./scripts/check.sh
./scripts/check.sh checks
./scripts/check.sh system arch-pc
nix --extra-experimental-features 'nix-command flakes' build --no-link path:.#checks.x86_64-linux.subscription
nix --extra-experimental-features 'nix-command flakes' build --no-link path:.#xlog path:.#dingtalk path:.#chatgpt-desktop
nix --extra-experimental-features 'nix-command flakes' build --no-link path:.#nixosConfigurations.arch-pc.config.system.build.toplevel
```

检查脚本使用 path flake，使新文件在暂存前也可求值，保持既有 Git index。提交时仍需加入新文件。构建通过后也需验证工作网络、DAE eBPF、Hysteria 远端15023、会议/共享、桌面登录与锁屏、实际项目构建和恢复路径。

本轮授权范围是配置实现和迁移准备；不执行 `switch`、`boot`、`nixos-install`、分区或旧系统清理。
