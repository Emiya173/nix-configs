# 多主机 NixOS 配置

使用 Flake、NixOS 模块、nix-wrapper-modules 和 Hjem 管理私人电脑与工作机，统一 **niri + DankMaterialShell（DMS）** 桌面、中文输入、终端和开发工具，并按主机选择硬件、网络服务与应用。

当前支持 `x86_64-linux`。基础包集为 `nixos-26.05`，部分应用显式使用 `nixpkgs-unstable`；输入的具体提交由 [flake.lock](flake.lock) 锁定。Home Manager 已从配置中移除；系统集成、程序 wrapper 与剩余用户文件均由同一套 NixOS 配置组装。

## 主机与功能

| 主机 | 用途与硬件 | 主机专属配置 |
| --- | --- | --- |
| [`present-pc`](hosts/present-pc/configuration.nix) | 私人电脑，AMD 显卡，双 DP 显示器 | AMD/ROCm、Steam/Lutris/Wine、Waydroid、Sunshine、Scratch 工作区、投屏与虚拟输出、VoidMaker 入口 |
| [`arch-pc`](hosts/arch-pc/configuration.nix) | 工作机，Intel UHD 770，单 HDMI 显示器 | 工作应用、Android/ADB 工具、xlog、DAE 自动订阅、EasyConnect、Hysteria 与反向隧道、wayvnc |

两台主机共享桌面与基本操作习惯，工作机关闭娱乐功能、Scratch、投屏和 VoidMaker 入口。功能选择集中在 [flake.nix](flake.nix) 的 `desktopFeatures`；硬件与系统服务由各自主机的模块导入和覆盖决定。

### 共享环境

- **桌面**：niri 滚动平铺、DMS 面板/启动器/通知/剪贴板/壁纸/动态主题、DankGreeter 登录和 DMS 锁屏；通过 XWayland Satellite 运行 X11 应用。
- **中文与外观**：Fcitx5 + Rime，雾凇词库、小鹤双拼、默认简体；中文 locale、CJK/Nerd 字体、GTK/Qt 主题和应用缩放配置。
- **终端**：Kitty、Fish、Starship、Atuin 历史搜索、fzf、zoxide、bat、eza、Yazi、lazygit，以及 nix-index/comma 命令查找。
- **开发**：VS Code、Android Studio、Nixvim、Git、direnv/nix-direnv；Rust、Node.js、Java、Python、C/C++、Go、Zig、Haskell、Typst 等工具。项目自己的 devShell 与 lock 由各项目维护。
- **应用**：Chromium、Brave、WPS、QQ、飞书、百度网盘、ChatGPT/Codex 桌面入口与独立 Codex CLI；Dolphin、Ark、OBS、ffmpeg、mpv、imv/gthumb、Satty 等文件和媒体工具。
- **系统**：CachyOS LTO 内核、UEFI GRUB、zram 与磁盘 swap、PipeWire、NetworkManager、蓝牙、Tailscale、OpenSSH、Docker、nix-ld 和 AppImage 支持。

两台主机共用 `linuxPackages-cachyos-latest-lto-x86_64-v3`，使用 Clang ThinLTO 与适合 Intel i7-14700 / i5-13490F 的 x86-64-v3 指令集。内核来自 [nix-cachyos-kernel 的 release 分支](https://github.com/xddxdd/nix-cachyos-kernel/tree/release)，保留其自带 Nixpkgs 以匹配补丁和预编译缓存。`latest` 是包名；实际版本、源码、补丁和工具链由 `flake.lock` 固定，更新内核需显式执行 `nix flake update nix-cachyos-kernel`。私人主机继续启用 `scx_lavd`。

系统无衬线界面统一使用华为官方 HarmonyOS Sans SC，覆盖简体中文、英文和数字；GTK、Qt、DMS 与飞书同步使用该字体及其原生字重。等宽字体统一为 FiraCode Nerd Font Mono，中文回退到 Noto Sans Mono CJK SC；Kitty、VS Code、JetBrains/Android Studio 和 Qt 固定字体由共享配置同步。原用户字体、编辑器与主题配置在首次修改前备份，应用的其他设置保留。

等宽字体的包定义与下载校验值由 `flake.lock` 锁定的 Nixpkgs 固定：当前 FiraCode Nerd Font 为 `3.4.0+6.2`，Noto CJK 为静态版 `2.004`。Fontconfig 只允许这两个等宽字族使用对应 Nix store 包中的文件，同名字族的用户目录副本不会参与匹配，原文件仍保留。系统与 Hjem 管理的用户 Fontconfig 共用该来源规则；无需从旧机器复制字体或手动下载，更新锁文件后才可能随包集升级。

HarmonyOS Sans 使用未修改的华为官方字体，许可随字体包保存在 `share/licenses/harmonyos-sans-sc/LICENSE.txt`。飞书继续通过独立 Fontconfig 配置覆盖其显式字体名并关闭字形亚像素定位，副本位于 `~/.config/feishu/fontconfig.conf`。

工作机另外提供 Beyond Compare、钉钉、腾讯会议、LocalSend、JDK 11、Maven、ADB 脚本和 xlog 解码工具。私人主机另外提供游戏、串流及 Blender 等应用。完整包清单见 [modules/packages.nix](modules/packages.nix)、[modules/user/packages.nix](modules/user/packages.nix)、[modules/user/desktop.nix](modules/user/desktop.nix)、[modules/user/dev.nix](modules/user/dev.nix) 和 [hosts/arch-pc/user.nix](hosts/arch-pc/user.nix)。

## 配置结构

```text
.
├── flake.nix / flake.lock       # 输入、主机组装、功能选择和构建输出
├── hosts/
│   ├── present-pc/
│   └── arch-pc/
│       ├── configuration.nix   # 主机系统入口与覆盖
│       ├── hardware-configuration.nix
│       ├── displays.nix        # 输出名称、模式、缩放、位置和主屏
│       ├── paths.nix           # 用户目录、仓库和外部项目路径
│       └── user.nix            # 需要时添加的主机专属用户设置
├── modules/                    # 可复用的 NixOS 模块
│   ├── user/                   # 共享用户环境，入口为 default.nix
│   │   ├── wrappers.nix        # Kitty、Fastfetch、btop 的配置包
│   │   ├── niri.nix            # niri 序列化、wrapper 与 DMS 集成
│   │   └── home.nix            # Hjem 文件、XDG 目录与旧 HM 链接移交
│   └── workstation/            # 工作机网络及 DAE 服务
├── overlays/                   # 包集覆盖和 unstable 入口
├── packages/                   # 自定义打包、补丁和工作脚本
├── assets/                     # 静态资源与冻结的旧 HM 文件允许清单
├── scripts/                    # 验证、维护和链接移交脚本
└── tests/                      # 订阅恢复、隐私与链接移交测试
```

[flake.nix](flake.nix) 中的 `mkHost` 为每台主机加载系统入口和 [modules/user/default.nix](modules/user/default.nix)，通过 NixOS `specialArgs` 传入 `userName`、`hostName`、`displayConfig`、`hostPaths` 和 `desktopFeatures`。主机专属用户设置由主机系统入口显式导入；目前工作机使用 [hosts/arch-pc/user.nix](hosts/arch-pc/user.nix)，私人主机直接使用共享设置。

配置按以下顺序分工：

1. **NixOS module 优先**：shell 及其集成、Git 通用设置、Yazi、lazygit、Nixvim、用户包和 systemd 用户服务放在 `modules/user/` 的对应模块中；主机差异放在 `hosts/<hostname>/user.nix`。
2. **nix-wrapper-modules**：缺少合适系统配置接口的 Kitty、Fastfetch、btop 和 niri 配置打成独立包。niri 继续复用锁定 niri-flake 的类型与 KDL 序列化，NixOS 模块负责会话、portal 和服务集成。
3. **Hjem**：处理剩余固定位置的文件链接，包括 GTK 设置、字体、应用 flags、MIME、Rime 配置和兼容入口。个人 Git identity 仍只写入用户的 `~/.config/git/config`，见 [modules/user/home.nix](modules/user/home.nix)；共享 Git 行为在 [modules/user/git.nix](modules/user/git.nix)。

DMS 的设置、壁纸状态、Kitty 的 `dank-theme.conf` / `dank-tabs.conf`、GTK CSS 和 Qt 配色文件保持可写；Hjem 不链接整个动态主题目录。Kitty wrapper 显式读取用户目录中的 DMS 文件。`~/.config/niri/config.kdl` 是同一份声明式配置的只读镜像，供 DMS 显示快捷键与窗口规则。

### 修改入口

| 要调整的内容 | 配置位置 |
| --- | --- |
| 磁盘 UUID、挂载、内核硬件模块、主机硬件支持 | `hosts/<hostname>/hardware-configuration.nix` |
| 显示器名称、分辨率、刷新率、缩放和位置 | `hosts/<hostname>/displays.nix` |
| 用户 home、仓库位置、VoidMaker 源码目录 | `hosts/<hostname>/paths.nix` |
| 共享启动、网络、音频、输入法、用户和系统服务 | [modules/](modules/) |
| 主机专属服务、防火墙与系统覆盖 | `hosts/<hostname>/configuration.nix`，工作网络在 [modules/workstation/](modules/workstation/) |
| 共享终端、应用、开发工具、编辑器与文件管理器 | [modules/user/](modules/user/) 中的对应模块 |
| 主机专属应用、Fish alias/PATH 和用户服务 | `hosts/<hostname>/user.nix` |
| niri 快捷键、窗口规则、输入设备和 DMS 集成 | [modules/user/niri.nix](modules/user/niri.nix) |
| GTK/Qt、光标、默认应用与 Rime 用户配置 | [modules/user/desktop.nix](modules/user/desktop.nix) |
| 自定义包、补丁与包集选择 | [packages/](packages/)、[overlays/default.nix](overlays/default.nix) |

`paths.nix` 中的路径是运行时字符串，外部源码目录不会因此复制进 Nix store。改变仓库位置后也应更新这里的 `repository`，供 `NH_FLAKE` 和 Fish 维护命令使用。

niri 的快捷键、显示器、光标和窗口规则在 [modules/user/niri.nix](modules/user/niri.nix) 中声明并由 wrapper 加载；修改对应 Nix 文件后重建。DMS 设置面板负责壁纸、面板、动态主题和电源/空闲超时等可变状态；其中接管 niri 配置的导入提示可以关闭。

## 构建与切换

在已安装 Nix、启用 `nix-command` 和 `flakes` 的环境中获取仓库：

```bash
git clone https://github.com/Emiya173/nix-configs.git
cd nix-configs
./scripts/check.sh
```

以下命令均在仓库目录执行。现有主机的 hostname 与 flake 输出同名，`nh` 可选择本机配置：

```bash
nh os build .                 # 构建并查看差异
nh os switch .                # 构建并激活系统与用户配置
```

首次启用 CachyOS 内核时，系统尚未配置对应缓存，构建命令需临时带上上游缓存地址与签名公钥，避免本地编译内核：

```bash
nh os build . \
  --option extra-substituters 'https://attic.xuyh0120.win/lantian?priority=60 https://cache.xinux.uz?priority=70' \
  --option extra-trusted-public-keys 'lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc= cache.xinux.uz:BXCrtqejFjWzWEB9YuGB7X2MV4ttBur1N8BkwQRdH+0='
nh os switch .
```

主缓存和上游文档列出的备用缓存分别使用公布的签名公钥校验；切换后，缓存设置由 [modules/nix.nix](modules/nix.nix) 持久管理。新内核需重启后运行；GRUB 中的旧系统代次仍可用于回退。

也可以明确指定目标。构建另一台主机的系统不会激活它：

```bash
nix build --no-link .#nixosConfigurations.present-pc.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.arch-pc.config.system.build.toplevel

# 在对应目标主机上激活，以工作机为例
sudo nixos-rebuild switch --flake .#arch-pc
```

Git 仓库形式的 flake 只包含已跟踪的文件，新增模块或资源应先 `git add`，无需先提交。[scripts/check.sh](scripts/check.sh) 使用 `path:` 输入，能够在不修改暂存区的情况下检查新增文件。

### 从 Home Manager 首次切换

2026-10-16 的迁移验证记录：阶段 1（NixOS 原生模块）与阶段 2（wrapper、niri/DMS）均已通过两台主机完整求值，两个 niri wrapper 也已构建并通过 `niri validate`。移除 HM 并完成环境变量收尾后的最终求值、4 项 flake checks 和两台完整系统构建均已通过。两台主机的临时 home 移交演练、连续两次 Hjem 激活和实际服务依赖图验证也已通过，动态 Kitty 文件保留。这些检查没有激活本机配置，图形会话行为仍需首次切换后验收。

[modules/user/home.nix](modules/user/home.nix) 将旧链接移交安排在 Hjem 激活之前。[scripts/migrate-home-manager.py](scripts/migrate-home-manager.py) 仅处理 [assets/home-manager-files/](assets/home-manager-files/) 中对应主机的冻结允许清单：路径必须仍是直接指向 `/nix/store/<hash>-home-manager-files/<同一相对路径>` 的 symlink，损坏的旧链接也可识别。普通文件、其他来源的链接和 symlink 父目录都会保留，脚本不递归清理配置目录。

每次有匹配项时，原 symlink 会移至 `~/.local/state/home-manager-migration/<唯一运行目录>/files/`，同目录 `manifest.json` 记录原路径、链接目标和处理状态。没有匹配项时不创建新备份；旧系统回滚后重新生成的 HM 链接可在下次切换时再次移交。Hjem 默认不覆盖其他来源的现有文件；遇到冲突应先查看日志、确认原文件用途再处理。仓库既有字体与 MIME 的显式接管例外在对应模块中保留。

首次切换前，保留当前可启动的系统代次和迁移备份。若需要还原整个 home，应先准备可用的 `@home` 快照；链接移交备份只保存被移开的旧 HM symlink，不包含应用可变数据。按以下顺序完成验证：

```bash
# 将本次需要的新模块、资源和脚本纳入 Git 跟踪，无需先提交。
git add flake.nix flake.lock modules/user hosts/arch-pc/user.nix \
  assets/home-manager-files scripts/migrate-home-manager.py tests/test_home_migration.py

./scripts/check.sh eval
./scripts/check.sh checks
./scripts/check.sh system present-pc
./scripts/check.sh system arch-pc

# 检查差异后，由用户在对应主机上显式切换；以下以工作机为例。
sudo nixos-rebuild switch --flake .#arch-pc
```

切换后退出并重新登录，检查 niri 显示器/快捷键、DMS 启动与锁屏、Kitty 动态主题、Fish 集成、输入法和工作机 wayvnc。可查看 `journalctl -u hjem-migrate-present.service -u hjem-activate@present.service`，以及 `journalctl --user -u dms.service -u niri.service`；本仓库实现迁移时不自动执行切换或清理旧代次。

跨越 HM → Hjem 迁移回退时，使用 `nixos-rollback`（Fish 的 `nor`）。它默认只预览目标代次、包差异和 home 冲突，`--apply` 才会执行。目标包含旧 HM 服务时，工具读取该代实际的 `home-files`，仅处理冻结允许清单与目标文件树的交集：将现有非 HM 文件或 symlink 移到 `~/.local/state/home-manager-migration/<唯一运行目录>/files/`，在 manifest 中记录 `prepare-rollback`，再激活指定代次。已有 `*.hm-backup` 保留，后续用户修改保存在新的备份中；目录或 symlink 父路径冲突会在移动前报错。

```bash
nh os info
nixos-rollback --to 27          # 示例：先预览想恢复的代次
nixos-rollback --to 27 --apply  # 备份冲突文件并回退，随后重新登录
```

如果已经从 GRUB 启动旧代，或一次失败的回退造成运行配置与系统 profile 不一致，可在本仓库执行 `bash scripts/rollback-system.sh --to 27 --apply`。目标已是当前 profile 时，工具会完成该代的激活，不会再退一代。请用普通用户运行，工具在移动文件前获取 sudo 权限。若激活仍然失败，保留输出中的备份目录；检查错误后可重试同一目标。

直接运行 `nh os rollback` 或从 GRUB 选择旧代仍不会撤销 home 中的文件变更；旧系统代次不可变，无法给它补装新的恢复逻辑。上述工具用于跨迁移回退，不恢复全部应用数据；完整 home 恢复仍使用事先准备的 `@home` 快照。旧代次、迁移备份在新会话验收前都应保留。

迁移后的登录器显式优先使用包含 Qt QML 依赖的 Quickshell 包装器和独立的 Niri，避免系统 PATH 中的普通 `qs` 抢先被选中。flake 的 `greeter` 检查在独立的无屏幕 Wayland 环境启动实际登录器；`home-migration` 检查覆盖冲突备份、旧 `.hm-backup` 保留和 HM → Hjem → HM → Hjem 的文件交接。

### 更新与格式化

```bash
nix flake update              # 更新所有输入的锁定版本
# 或只更新一个输入
nix flake update nixpkgs-unstable

./scripts/check.sh
nh os build .
nh os switch .

nix develop                   # 仓库维护环境：nixfmt、ShellCheck
nix fmt -- flake.nix           # 格式化指定 Nix 文件
```

提交前检查 `flake.nix` 和 `flake.lock` 的变化。发行版升级使用 `./scripts/bump-release.sh <YY.05 或 YY.11>`，例如 `./scripts/bump-release.sh 26.11`；它同步 nixpkgs、Nixvim 的 release URL 和 lock，然后执行求值检查。应先确认目标分支存在，并继续完成 checks 与目标系统构建。

`system.stateVersion` 记录系统状态兼容基线，不随发行版升级自动修改。私人主机保持 `25.11`，工作机保持 `26.05`；移除 Home Manager 不改变这些值。

## 验证与自定义包

[scripts/check.sh](scripts/check.sh) 提供独立验证层级，均禁止自动更新 lock：

| 命令 | 检查范围 |
| --- | --- |
| `./scripts/check.sh` 或 `./scripts/check.sh eval` | 求值所有 flake 输出与两台主机的完整系统配置，不构建应用或系统 |
| `./scripts/check.sh checks` | 构建 flake checks：Nix 格式、维护脚本 ShellCheck、订阅恢复与隐私测试、旧 HM 链接移交测试 |
| `./scripts/check.sh packages` | 构建全部 8 个维护包 |
| `./scripts/check.sh packages codex dae-subscription` | 只构建指定维护包 |
| `./scripts/check.sh system arch-pc` | 构建工作机完整系统，不激活 |
| `./scripts/check.sh all arch-pc` | 依次求值、构建 checks、全部维护包与工作机系统 |

`system` 和 `all` 省略主机名时默认选择 `present-pc`。每次修改至少通过求值检查；包变更增加目标包构建，服务、桌面、图形和启动变更增加对应完整系统构建。订阅测试位于 [tests/test_subscription.py](tests/test_subscription.py)，链接移交测试位于 [tests/test_home_migration.py](tests/test_home_migration.py)，后者只在 `/tmp` 的隔离 home 中运行。协作约定见 [AGENTS.md](AGENTS.md)。

flake 导出的维护包均可通过 `nix build --no-link .#<包名>` 单独构建：

| 输出 | 维护内容 |
| --- | --- |
| `qq` | unstable QQ，注入原生 Wayland 和输入法参数 |
| `codex` | 官方 Codex CLI 发布包，单独固定版本和 SHA-256 |
| `baidunetdisk` | 百度网盘打包及启动参数支持 |
| `fastfetch` | 基于上游包增加本地 Nix profile 缓存补丁 |
| `dingtalk` | 钉钉桌面包 |
| `chatgpt-desktop` | ChatGPT/Codex 桌面客户端的 NixOS FHS 运行环境 |
| `xlog` | 随仓库保存的 Haskell 源码、构建与原项目测试 |
| `dae-subscription` | 本地订阅中继、同步、缓存和 DAE 应用逻辑 |

更新固定发布包时同步版本与源码校验值，再执行求值和目标包构建。DAE、Hysteria 等直接跟随已锁定的 unstable 包集；具体选择见 overlay 和相应服务模块。

## 桌面与终端操作

`Mod` 为 Super/Win。常用共享快捷键如下，完整设置见 [modules/user/niri.nix](modules/user/niri.nix)：

| 快捷键 | 操作 |
| --- | --- |
| 轻点左 Super / `Mod+Space` | DMS 启动器；按住 Super 仍作为修饰键 |
| `Mod+V` | 剪贴板历史 |
| `Mod+I` / `Mod+/` | DMS 设置 / 快捷键面板 |
| `Mod+Tab` | niri 工作区总览 |
| `Mod+Alt+L` | 锁屏 |
| `Mod+BackSpace` | 电源菜单 |
| `Print` / `Mod+Shift+S` | 区域截图 |
| `Ctrl+Print` / `Alt+Print` | 全屏 / 窗口截图 |
| `Mod+Shift+A` | 区域截图后用 Satty 标注 |

私人主机另有 Scratch、投屏与 VoidMaker 快捷键。VoidMaker 的运行服务由外部项目维护，本仓库声明启动入口和源码路径。

Fish 中 `Ctrl+R` 由 Atuin 搜索历史；`y` 启动 Yazi 并在退出时切换目录。系统维护缩写在输入空格时展开为可见命令：

| 缩写 | 命令用途 |
| --- | --- |
| `nob` / `nos` | `nh os build` / `nh os switch`，仓库路径由 `NH_FLAKE` 提供 |
| `nfu` / `nfc` / `nfs` | 更新输入 / 构建 flake checks / 查看输出 |
| `ngc` | 按现有保留策略执行 `nh clean all` |
| `ntree` / `nwhy` | `nix-tree` / `nix why-depends` |
| `ndev` | 进入当前项目的 `nix develop` |

工作机还提供 `adbs=adb shell`、`rn=Perl rename`、`tar=bsdtar`、`pip=uv pip`，以及 `~/script`、ADB 和 ghcup 的兼容路径；JDK 11/21 可通过 `~/.local/share/jdks/` 明确选择。

## 工作机网络服务与私密状态

工作网络集中在 [modules/workstation/](modules/workstation/)，其运行配置、账号和密钥独立保存在目标主机：

- **DAE**：本地中继提供有效缓存，后台自动获取、校验订阅并 reload；网络失败按退避期限重试，保留现有缓存。上游 URL 位于 `/var/lib/dae-subscription-config/upstream-url`，通过 systemd credential 加载，修改后自动触发同步，无需手动依次启动 Python 与 DAE。
- **EasyConnect**：systemd 管理现有 Compose 项目，并等待、初始化 VPN DNS；Compose 文件和登录状态属于主机本地数据。
- **Hysteria**：使用 `/etc/hysteria/` 下的运行配置和密钥，分别维护客户端、反向 SSH 与 VNC 隧道。wayvnc 是随图形会话启动的用户服务。
- **NetworkManager**：持久连接及其凭据保存在主机运行目录。工作机另有局域网 ADB/scrcpy 的接口防火墙规则。

DAE 健康状态可通过 `curl -fsS http://127.0.0.1:8080/health` 查看；结合 `fallback`、`fetched_at` 和 `sync` 判断是否已获取真实订阅及是否处于退避。详细的服务、凭据路径、远程连接命令与历史安装记录见 [WORKSTATION.md](WORKSTATION.md)。

仓库声明软件和配置结构；登录密码 hash、SSH/GPG/ADB 私钥、订阅 URL、VPN 凭据、xlog 解码密钥及应用登录状态不写入 Git 或 Nix store。用户文件、DMS 可变设置、Rime 学习数据、SDK 和外部工具链也有各自的运行状态，需要在目标主机独立准备或保留。

## 存储与日常维护

### Btrfs 快照

现有主机均将 home、Nix store 和快照拆为独立子卷，实际设备 UUID 与挂载参数以各自硬件配置为准：

| 挂载点 | `present-pc` | `arch-pc` |
| --- | --- | --- |
| `/` | `@` | `@nixos` |
| `/home` | `@home` | `@home` |
| `/nix` | `@nix` | `@nix` |
| `/snapshots` | `@snapshots` | `@snapshots` |
| `/btrfs` | 顶层 `subvolid=5` | 顶层 `subvolid=5` |
| `/boot` | 本机 ESP | 本机 ESP |

`btrbk-local.timer` 每小时运行，快照写入 `/snapshots`；私人主机策略在 [modules/snapshots.nix](modules/snapshots.nix)，工作机在其系统入口中声明：

| 源子卷 | 创建方式 | 保留策略 |
| --- | --- | --- |
| `@home` | 每次运行创建 | 最近 24 小时、7 天、4 周分层保留，最小保留窗口 2 小时 |
| 根子卷 `@` / `@nixos` | 有变化时创建 | 最近 12 小时、3 天分层保留，最小保留窗口 2 小时 |
| `@nix` | 不创建快照 | 由 Nix 构建与垃圾回收管理 |

这是同一文件系统内的本地快照，当前没有异机备份目标。两台主机另有每周 Btrfs scrub、SMART 监控和 fstrim。

```bash
systemctl status btrbk-local.timer
journalctl -u btrbk-local.service
sudo btrfs subvolume list /snapshots
sudo systemctl start btrbk-local.service   # 手动执行一次当前策略
```

### Nix 空间与依赖

[modules/nix.nix](modules/nix.nix) 启用 store 自动优化，并由 `nh clean` 定时清理，保留参数为 `--keep 5 --keep-since 14d`。旧 generation、profile 和其他 GC root 会影响可回收空间。

```bash
nix-tree /run/current-system
nix path-info -rSh /run/current-system
nix why-depends /run/current-system /nix/store/<目标路径>
```

依赖的 closure 大小包含共享依赖，不能逐项相加当作实际磁盘占用。Btrfs 快照保留的旧数据也独立影响文件系统剩余空间。

Docker 两台主机都启用；私人主机启用镜像自动清理，工作机关闭 `autoPrune`。容器内容与卷属于运行数据，生命周期由对应项目维护。

## 适配与部署新主机

复用配置时，先准备目标主机的硬件、挂载、用户和运行凭据。仓库中的设备 UUID、显示器名称与路径均对应已有机器。

1. 新建 `hosts/<hostname>/` 的系统入口、硬件配置、`displays.nix` 和 `paths.nix`，选择所需共享模块。可用 `nixos-generate-config` 获取目标硬件信息，再核对实际挂载。
2. 如有主机专属应用、用户服务或覆盖，新建 `hosts/<hostname>/user.nix` 并从该主机的 `configuration.nix` 显式导入；没有差异时可直接使用共享用户模块。
3. 在 `flake.nix` 中注册 `nixosConfigurations.<hostname> = mkHost "<hostname>"`，设置功能选择；改变用户名或架构时同步调整入口参数。
4. 添加 `assets/home-manager-files/<hostname>.json`。`modules/user/home.nix` 按主机名读取该清单；没有 HM 历史的新主机使用 `{"version": 1, "host": "<hostname>", "targets": []}`。有旧部署时从旧 HM 文件清单冻结允许路径，不要从新 Hjem 配置反推。
5. 更新 [scripts/check.sh](scripts/check.sh) 中的主机枚举和完整求值列表，执行求值、checks 与目标系统构建。
6. 在目标系统使用 `nixos-rebuild --flake` 激活；首次安装时，在安装环境正确挂载目标到 `/mnt`，准备登录凭据及服务所需私密文件后，使用 `nixos-install --flake` 指定目标主机。

工作机专属的状态导入与安装预检脚本仅用于其既定流程，说明保留在 [WORKSTATION.md](WORKSTATION.md)。日常更新使用本 README 的构建、验证和切换入口。
