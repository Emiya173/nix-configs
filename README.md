# 多主机 NixOS 配置

使用 Flake、NixOS 模块、nix-wrapper-modules 和 Hjem 管理私人电脑与工作机，统一 **niri + DankMaterialShell（DMS）** 桌面、中文输入、终端和开发工具，并按主机选择硬件、网络服务与应用。

当前支持 `x86_64-linux`。基础包集为 `nixos-26.05`，部分应用显式使用 `nixpkgs-unstable`；输入的具体提交由 [flake.lock](flake.lock) 锁定。

## 主机与功能

| 主机 | 用途与硬件 | 主机专属配置 |
| --- | --- | --- |
| [`present-pc`](hosts/present-pc/configuration.nix) | 私人电脑，AMD 显卡，双 DP 显示器 | AMD/ROCm、Steam/Lutris/Wine、Waydroid、Sunshine、投屏与虚拟输出、VoidMaker 入口 |
| [`arch-pc`](hosts/arch-pc/configuration.nix) | 工作机，Intel UHD 770，单 HDMI 显示器 | 工作应用、Android/ADB 工具、xlog、DAE 自动订阅、EasyConnect、Hysteria 与反向隧道、wayvnc |

两台主机共享桌面与基本操作习惯，工作机关闭娱乐功能、投屏和 VoidMaker 入口。功能选择集中在 [flake.nix](flake.nix) 的 `desktopFeatures`；硬件与系统服务由各自主机的模块导入和覆盖决定。

### 共享环境

- **桌面**：niri 滚动平铺，DMS 面板、启动器、通知、剪贴板、壁纸与动态主题，DankGreeter 登录和 DMS 锁屏；通过 XWayland Satellite 运行 X11 应用。
- **中文与外观**：Fcitx5 + Rime、雾凇词库与小鹤双拼；HarmonyOS Sans SC 界面字体、FiraCode Nerd Font Mono 等宽字体及 Noto CJK 中文回退。
- **终端**：Kitty、Fish、Starship、Atuin、fzf、zoxide、bat、eza、Yazi、lazygit，以及 nix-index/comma 命令查找。
- **开发**：VS Code、Android Studio、Git、direnv/nix-direnv，以及 Rust、Node.js、Java、Python、C/C++、Go、Zig、Haskell、Typst 等工具；项目自己的 devShell 与 lock 由各项目维护。
- **编辑器**：Nixvim 提供语言服务、补全与格式化、日志高亮、Markdown 浏览器预览、Git 改动与 blame、跨文件搜索替换、会话恢复、标记显示、大文件模式和浮动终端；which-key 提供英文分组与图标提示。
- **应用**：Chromium、Brave、WPS、QQ、飞书、百度网盘、ChatGPT/Codex 桌面入口与独立 Codex CLI；Dolphin、Ark、OBS、ffmpeg、mpv、图像查看与截图工具。
- **系统**：CachyOS LTO 内核、UEFI GRUB、zram 与磁盘 swap、PipeWire、NetworkManager、蓝牙、Tailscale、OpenSSH、Docker、nix-ld 和 AppImage 支持。

两台主机共用 [nix-cachyos-kernel release 分支](https://github.com/xddxdd/nix-cachyos-kernel/tree/release)的 x86-64-v3 内核，私人主机另外启用 `scx_lavd`。版本、源码与工具链随 flake 输入锁定；缓存配置见 [modules/nix.nix](modules/nix.nix)。

工作机另有 Beyond Compare、钉钉、腾讯会议、LocalSend、JDK 11、Maven、ADB 脚本和 xlog 解码工具；私人主机另有游戏、串流及 Blender 等应用。完整包清单见 [modules/packages.nix](modules/packages.nix)、[modules/user/packages.nix](modules/user/packages.nix)、[modules/user/desktop.nix](modules/user/desktop.nix)、[modules/user/dev.nix](modules/user/dev.nix) 和 [hosts/arch-pc/user.nix](hosts/arch-pc/user.nix)。

## 配置结构

```text
.
├── flake.nix / flake.lock       # 输入、主机组装、功能选择和构建输出
├── hosts/<hostname>/
│   ├── configuration.nix       # 主机系统入口与覆盖
│   ├── hardware-configuration.nix
│   ├── displays.nix            # 显示器配置
│   ├── paths.nix               # 用户目录、仓库和外部项目路径
│   └── user.nix                # 可选的主机专属用户设置
├── modules/
│   ├── user/                   # 共享用户环境，入口为 default.nix
│   └── workstation/            # 工作机网络及 DAE 服务
├── overlays/                   # 包集覆盖和 unstable 入口
├── nur/                        # 独立 Git submodule：软件包、补丁与测试
├── packages/                   # 系统专用订阅中继和工作脚本
├── assets/                     # 静态资源
├── scripts/                    # 验证和维护工具
└── tests/                      # 自动化测试
```

[flake.nix](flake.nix) 中的 `mkHost` 加载主机系统入口和共享用户环境，通过 `specialArgs` 传入主机路径、显示器与功能选择。主机专属用户设置从其系统入口显式导入。

配置优先使用原生 NixOS 模块；Kitty、Fastfetch、btop 和 niri 使用 nix-wrapper-modules；Hjem 管理剩余固定位置的文件链接。DMS 设置、GTK CSS、Qt 配色和 Kitty 动态主题保持可写。个人 Git identity 位于用户配置中，共享行为由 [modules/user/git.nix](modules/user/git.nix) 管理。

### 修改入口

| 要调整的内容 | 配置位置 |
| --- | --- |
| 硬件、磁盘 UUID 与挂载 | `hosts/<hostname>/hardware-configuration.nix` |
| 显示器与主机运行路径 | `hosts/<hostname>/displays.nix`、`paths.nix` |
| 主机专属服务与系统覆盖 | `hosts/<hostname>/configuration.nix` |
| 主机专属应用、shell 与用户服务 | `hosts/<hostname>/user.nix` |
| niri 窗口、输入与 DMS 集成 | [modules/user/niri.nix](modules/user/niri.nix) |
| 终端、shell 与文件管理器 | [wrappers.nix](modules/user/wrappers.nix)、[shell.nix](modules/user/shell.nix)、[yazi.nix](modules/user/yazi.nix) |
| Nixvim 插件、行为与快捷键 | [modules/user/nvim.nix](modules/user/nvim.nix) |
| Fcitx5、Rime 方案与词库 | [input-method.nix](modules/input-method.nix)、[用户输入法配置](modules/user/input-method.nix) |
| 外观、默认应用与字体 | [desktop.nix](modules/user/desktop.nix)、[fonts.nix](modules/user/fonts.nix) |
| 用户文件与 XDG 目录 | [modules/user/home.nix](modules/user/home.nix) |
| 自定义包与包集选择 | [nur/](nur/)、[overlays/default.nix](overlays/default.nix) |

## 构建与验证

需要已安装 Nix，并启用 `nix-command` 和 `flakes`：

```bash
git clone --recurse-submodules https://github.com/Emiya173/nix-configs.git
cd nix-configs
./scripts/check.sh

nh os build .                 # 构建并查看差异
nh os switch .                # 在目标主机激活配置
```

已有 checkout 使用 `git submodule update --init --recursive` 初始化 `nur/`。现有主机的 hostname 与 flake 输出同名，`nh` 可选择本机配置。Git 形式的 flake 只包含已跟踪文件；[scripts/check.sh](scripts/check.sh) 使用 `path:` 输入，可以检查尚未暂存的新增文件。

Fcitx5 默认选择 Rime，使用小鹤双拼、简体和锁定版本的雾凇词库，并通过 `rime-moegirl` 补充萌娘百科词条。萌娘词条最低词频设为 10,000，避免上游缺少词频时排在候选末尾；更高的上游词频保持不变。萌娘词库包、用户目录中的词库链接与导入关系一并声明，使 switch 前启动的 Fcitx5 也能找到新增词库，并保留原有的 `rime_ice` 学习词库名称。Hjem 管理用户 profile、Rime 补丁和词库入口；激活前自动将冲突旧文件保存到 `~/.local/state/fcitx5/config-handover-*/`，激活后通知当前 Fcitx5 会话重新部署。`rime_ice.userdb`、词频、同步数据和编译缓存保持可写，不纳入 Nix store。

| 命令 | 用途 |
| --- | --- |
| `./scripts/check.sh` | 求值 flake 输出与两台主机的完整配置，不构建系统 |
| `./scripts/check.sh checks` | 构建格式、脚本及自动化测试检查 |
| `./scripts/check.sh packages [包名…]` | 构建全部或指定维护包 |
| `./scripts/check.sh system <hostname>` | 构建指定主机的完整系统，不激活 |
| `nix flake update [输入名]` | 更新全部或指定输入的锁定版本 |
| `nix develop` | 进入包含 nixfmt、ShellCheck 的仓库维护环境 |

发行版升级入口为 [scripts/bump-release.sh](scripts/bump-release.sh)。`system.stateVersion` 是状态兼容基线，不随发行版自动更新。开发约定、验证要求与新增主机注意事项见 [AGENTS.md](AGENTS.md)。

## 自定义软件包

可复用软件包、补丁和测试在 [nur/](nur/) 独立维护，通过本地 overlay 使用本仓库的稳定包集。主要包括 Codex CLI、QQ、百度网盘、钉钉、ChatGPT/DeepSeek Harness 桌面版、DW-Proton、UMU、Fastfetch、nix-tree 补丁和 xlog。系统专用的 DAE 订阅中继等工具位于 [packages/](packages/)。

维护包通过 flake 的 `packages` 输出提供，可单独构建。NUR 的修改先在子模块提交和推送，再更新主仓库 gitlink；主仓库的 `nix flake update` 不会更新子模块。包说明与独立验证入口见 [nur/README.md](nur/README.md)。

## 工作机服务与运行状态

工作网络集中在 [modules/workstation/](modules/workstation/)，包括 DAE 订阅同步与缓存恢复、EasyConnect、Hysteria、反向 SSH/VNC 隧道及 wayvnc。服务、状态路径和部署说明见 [WORKSTATION.md](WORKSTATION.md)。

仓库声明软件与配置结构；登录密码 hash、SSH/GPG/ADB 私钥、订阅 URL、VPN 凭据、xlog 解码密钥及应用登录状态独立保存在目标主机，不写入 Git 或 Nix store。用户文件、DMS 可变设置、Rime 学习数据、SDK 和外部工具链也需要独立准备或保留。

## 存储与新主机

现有主机使用 Btrfs，将 home、Nix store 和快照放在独立子卷。btrbk 定时维护根目录与 home 的本地快照，并配合 scrub、SMART 监控和 fstrim；当前没有异机备份目标。具体布局见各主机硬件配置，私人主机的快照策略见 [modules/snapshots.nix](modules/snapshots.nix)。Nix store 自动优化与定时清理由 [modules/nix.nix](modules/nix.nix) 管理。

适配新主机时，在 `hosts/<hostname>/` 声明硬件、显示器、路径和主机差异，注册 flake 输出并补齐验证入口。现有 UUID、显示器名称和路径均对应已有机器，不能直接照搬；新主机所需清单及完整验证要求见 [AGENTS.md](AGENTS.md)。
