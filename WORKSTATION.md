# Arch 工作机迁移准备

本文保留 2026-10-12/13 的 Arch → NixOS 迁移计划和后续安装记录；其中 Home Manager、首次激活及当时验证范围的描述属于历史事实。2026-10-16 的去 HM 配置迁移、当前目录结构与首次切换流程见 [README.md](README.md#从-home-manager-首次切换)。工作机用户配置现位于 [hosts/arch-pc/user.nix](hosts/arch-pc/user.nix)，共享用户配置位于 [modules/user/](modules/user/)。

目标为 `arch-pc`，私人主机为 `present-pc`。桌面、Rime 输入法、DMS greeter 和锁屏来自审计固定的私人基准 `950423b`，保留多主机结构；工作机另外声明网络、应用与本地工具。执行验证不会激活 NixOS。

迁移只以新系统可用为目标，不要求 Arch 回退入口、迁移前快照、外置备份或恢复演练。原 `backup-manifest.tsv` 的泛化备份要求已撤销，实际数据处理按下文执行。

## 当前实现

- 实体屏 `HDMI-A-1`，2560×1440@74.968、scale1；Intel UHD770、Intel microcode 与 VAAPI。工作机不导入 AMD 或 gaming 模块。
- 工作机禁用 Waydroid/Sunshine，不安装 Wine/VirtualBox、Timeshift、旧 Python 环境和旧 MediaTek/I²C/虚拟摄像头定制。不带 Scratch、投屏/虚拟输出或 Mod+A 入口。
- Fish 保留所选工具链 PATH 与 `adbs`、Perl `rn`、`tar=bsdtar`、`pip=uv pip`。三份 ADB 脚本包装明确的 Bash/ADB/date 依赖，并管理原 `~/script` 入口；当时的首次 Home Manager 激活将同名旧文件改名为 `.hm-backup`，以便生成受管理文件。当前兼容入口由 `hosts/arch-pc/user.nix` 的 Hjem 文件声明提供，旧 HM 链接移交规则见 README。
- ADB server 的 TCP 5037 和 scrcpy 默认转发端口 TCP 27183–27199 在有线局域网接口 `enp1s0` 放行。需要共享 USB 设备时运行 `adb -a nodaemon server start`；其他机器用 `adb -H <工作机局域网地址> -P 5037 devices -l` 或 `shell` 访问本机 server。`adb connect` 用于连接设备端 adbd，不用于选择另一台电脑的 server。Windows PowerShell 投屏客户端先设置 `$env:ADB_SERVER_SOCKET = 'tcp:<工作机局域网地址>:5037'`，再运行 `scrcpy --tunnel-host=<工作机局域网地址>`；`--tunnel-host` 自动选择 ADB forward，视频/音频/控制连接使用上述转发端口，未固定 `--tunnel-port` 时会跟随实际选中的端口。
- 工作机 Atuin 使用已锁定 unstable 的版本，以兼容复用 home 中较新的历史库迁移；Ctrl+R 继续使用 Atuin 搜索。GHC 使用 nixpkgs 提供的版本，无需为 GHCup 配置额外的 nix-ld 运行库。
- JDK21 为默认命令，JDK11 以低优先级保留；项目可用 `~/.local/share/jdks/jdk11` 或 `jdk21` 明确选择 `JAVA_HOME`。
- xlog 源码已随仓库保存，依赖 zlib/zstd/OpenSSL3，以 Nix 构建并运行原项目测试，提供 `xlog` 和 `~/.local/bin/xlog`。实际解码密钥仍在 `~/.config/xlog/private.key`，不进仓库或 store。
- 增加 Beyond Compare、钉钉、腾讯会议、LocalSend、百度网盘与当前 Linux ChatGPT 桌面包；同一个桌面客户端包含 Codex 界面，并提供单独 Codex 桌面入口。CLI `codex` 继续独立提供。登录、界面、会议共享须在目标图形环境验收。
- 保留 OBS、ffmpeg-full、mpv、imv/gthumb/Satty/hyprpicker。DMS 已内建剪贴板粘贴，所选脚本/快捷键无 ydotool 调用，不迁移旧 ydotool 服务、用户组或专属配置；keyd 继续提供轻点 Super 启动器。移除 claude-code overlay 入口。Toolbox 应用、专属配置和 scripts PATH 不迁移，复用 home 时屏蔽旧菜单和自启动入口。
- 保留 NetworkManager 持久连接、DAE、EasyConnect、Hysteria/反向 SSH。WireGuard/wstunnel 退役，不迁移。Hysteria 反向 SSH 15023 保留，VNC 15903 由独立的 hysteria-vnc-tunnel.service 提供。该次迁移的 wayvnc 用户服务由 Home Manager 提供，随图形会话启动，沿用 0.0.0.0:5900；不增加防火墙放行，远程可通过 SSH 隧道访问。
- 工作机关闭 resolvconf 的 EDNS0 扩展：当前 EasyConnect DNS 对携带 OPT 的请求返回空答案，沿用迁移前 Arch 的普通 DNS 行为。
- DAE 使用已锁定 `nixpkgs-unstable` 中的包，不单独固定版本。工作配置通过运行时 credential 读取，不将含节点凭据的配置嵌入 Nix。
- EasyConnect 使用原 Compose 工作目录与系统 Docker socket，等待 VPN DNS 监听后初始化转发；DNS 以逐报文方式从 5353 转发至 Sangfor 5373 端口，子进程空闲 5 秒退出；从镜像重新创建容器，不要求搬迁旧匿名卷。旧 `ubuntu:doc_linux_60121` 镜像与 `aibox_build` 容器不迁移。Docker autoPrune 保持关闭。

## DAE 自动订阅

DAE 配置中的订阅入口保持 `http://127.0.0.1:8080/sub`。

订阅校验支持明文或 Base64 节点列表，包括本机上游提供的 AnyTLS；AnyTLS 省略端口时按协议使用443，不要求更换或单独固定 DAE 版本。

| 单元 | 行为 |
| --- | --- |
| dae-subscription.service | 仅监听 loopback，持续提供磁盘上的有效缓存，无需先联网；不持有上游 URL |
| dae-subscription-sync.service | 每次启动加载私密 URL credential，获取、解码并校验候选节点；成功后自动 reload DAE |
| dae-subscription-sync.timer | 每60秒检查恢复/待应用状态；正常获取间隔1小时，失败时按磁盘中的退避期限重试上游 |
| dae-subscription-config.path | 源文件变化触发同步，原子替换也覆盖；并发变更最终由后续检查收敛 |

DAE 首次启动不等待上游订阅：有有效或可恢复缓存时沿用缓存；没有缓存时，从私密配置中的 `ruruka` 静态节点生成兜底缓存，使默认代理可立即启动。订阅继续在后台重试，恢复后自动 reload 切回订阅节点。更新失败保留现有内容。候选与已应用状态分开保存，reload 失败还原发布缓存并保留候选重试。进程重启后重新核对应用状态。订阅同步程序不输出完整 URL、节点或原始异常。DAE 自身的日志策略仍来自私密配置。

HTTP 429 首次退避15分钟，之后30分钟、1小时；其他网络错误首次退避60秒并倍增，最长1小时。两者都遵循更长的 `Retry-After`（秒数或 HTTP 日期）。重试期限保存在 `fetch-state.json`，服务重启或 rebuild 不会重新请求；更换上游地址绕过旧地址的退避。已有有效缓存或兜底时，临时网络错误、HTTP 408/425/429/5xx 不阻断系统激活；没有有效缓存、认证等其他 HTTP 错误、无效订阅、凭据/状态文件错误和 DAE reload 失败仍返回失败。

上游地址只保存在 `/var/lib/dae-subscription-config/upstream-url`，root:root 0600，目录0700。安装准备时输入一次；之后更换这个私密文件即可，无需 rebuild 或手工按顺序启动服务。不要通过命令行参数、shell history 或 Git 保存完整订阅 URL。

缓存位于 `/var/lib/dae-subscription/`，0700/0600。上游请求不继承代理环境，避免首次启动依赖 DAE 的循环。`curl -fsS http://127.0.0.1:8080/health` 中的 `fallback` 标识是否使用静态兜底；`sync.degraded`、`sync.error`、`sync.http_status`、`sync.next_retry_at`（Unix 时间戳）显示上次获取失败及下次重试期限，成功获取后清除失败状态。健康只说明已有通过语法检查的节点，不证明所有节点远端可达；`degraded: false` 本身也不证明已成功获取订阅，应同时查看 `fallback` 和 `fetched_at`。

## Btrfs 与安装前提

当前配置是计划布局，尚未创建任何子卷或执行安装：

| 挂载点 | 子卷/设备 |
| --- | --- |
| / | @nixos，新建，旧 @ 仅作为迁移数据来源 |
| /home | @home，UID/GID1000 |
| /nix | @nix，新建 |
| /snapshots | @snapshots，新建 |
| /btrfs | Btrfs 顶层 subvolid=5 |
| /boot | 现有 ESP，UUID BC4C-93AB |

Btrfs UUID 为 `98fc4f2c-cd94-4e94-810e-7757fd903ee3`。安装环境必须再次生成并核对硬件配置，确认这些挂载和24GB swap UUID。安装后的 btrbk 仍沿用私人基准：每小时对 @home 和 **@nixos** 快照，home保留24h/7d/4w，根保留12h/3d，最小2h；@nix不快照，weekly scrub、smartd。不把这些日常策略作为迁移前备份步骤。

内存交换沿用私人基准：zram 优先（zstd、逻辑容量为内存的50%、priority5，按需分配实际内存），现有约24GiB磁盘 swap 仅作额外容量兜底。

在当前 Arch 中，将 @nixos 挂载为 /mnt 后运行 `sudo bash scripts/stage-workstation-state.sh /mnt`，直接导入 DAE/Hysteria、11份 NM profile、SSH host identity 与当前登录密码 hash。脚本读取当前 Arch 的 /etc 和用户数据库，应在进入安装 ISO 前执行。脚本拒绝运行根和非 @nixos 挂载，不创建子卷或启停服务；需要 root，尚未执行。没有现成订阅源文件时通过终端隐藏输入获取。

实际需要的数据处理：

| 对象 | 迁移方式 |
| --- | --- |
| 项目、用户 SSH/GPG/ADB keys、xlog 密钥、应用账号状态、SDK 与本仓库 | 直接复用 @home，UID/GID1000；无需额外复制 |
| DAE/Hysteria/NM 原件、登录密码 hash、SSH 主机身份 | 上述脚本直接导入新根的运行时路径，不进入 Git/Nix store |
| DAE 上游地址 | 隐藏输入一次；后续通过私密文件变更 |
| EasyConnect | 复用 home 中 Compose 配置，重新获取镜像并创建容器、初始化 DNS |
| Android 工具 | 复用 ~/Android/Sdk；ADB 由 Nix 提供并生成 /opt/android-sdk/platform-tools 兼容入口，不搬迁旧 /opt 二进制 |
| 旧构建镜像、aibox_build、旧 Docker 数据、Arch 启动材料和历史配置 | 不迁移，不作为安装前置 |

`scripts/preflight-workstation.sh /mnt` 只检查新系统所需文件、权限与挂载。安装顺序为：准备新子卷 → 在 Arch 导入运行凭据 → 安装环境挂载并核对硬件 → 预检 → 安装 → 工作能力验收。`@home` 直接复用，无需外置备份或单独的数据还原步骤。工作机不通过 os-prober 生成 Arch 启动入口；本轮不执行旧根清理。

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

检查脚本使用 path flake，使新文件在暂存前也可求值，保持既有 Git index。提交时仍需加入新文件。构建通过后也需验证工作网络、DAE eBPF、Hysteria 远端15023、会议/共享、桌面登录与锁屏和实际项目构建。

本轮授权范围是配置实现和迁移准备；不执行 `switch`、`boot`、`nixos-install`、分区或旧系统清理。

## 安装后排障记录（2026-10-13）

已在工作机 `/home/present/mirgate/nix-configs` 完成修复并激活：

- Codex CLI 0.160.0 的交互入口调用复用 home 中的 GNU app-server 缓存，因缺少 `libonig.so.5` 无法启动。执行 `codex app-server daemon update --from-cli --yes`，使用 Nix 安装的 musl 包替换并固定后台程序，再执行 `codex app-server daemon start`。交互请求和 shell 执行均已验证成功，认证和会话数据无需重置。以后升级 Nix 中的 Codex 包后，可再次执行 `codex app-server daemon update --from-cli --yes` 同步固定的后台程序。
- 原 `wayvnc.service` 调用已不存在的 `/usr/bin/wayvnc`，以 `203/EXEC` 失败。当时由 Home Manager 的 `services.wayvnc` 提供 Nix store 路径、图形会话自动启动和失败重启；旧用户单元保存为 `wayvnc.service.hm-backup`。该配置现已迁至 [hosts/arch-pc/user.nix](hosts/arch-pc/user.nix) 的 NixOS `systemd.user.services.wayvnc`。
- 完整访问链路为 `10.10.0.1:15900 → VPS 127.0.0.1:15903 → 工作机 127.0.0.1:5900`。迁移遗漏了 VNC 反向转发，现由 `modules/workstation/network.nix` 中独立的 `hysteria-vnc-tunnel.service` 补齐，经 Hysteria 10022 连接 VPS，沿用现有专用密钥。SSH 管理隧道的有效单元保持一致，VPS 和路由器配置无需改动。

远端 `./scripts/check.sh`、`./scripts/check.sh checks` 均通过；缓存站暂时不可达后，`nh os build . --offline` 成功。用户已执行 `nh os switch . --offline`，正式 VNC 隧道为 `active (running)`、`NRestarts=0`。本机实际执行 `wlvncc 10.10.0.1 15900` 成功连接，RFB 客户端收到 2560×1440 画面，用户再次确认远程访问成功。验证用临时隧道已停止。
