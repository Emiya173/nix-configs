# present-pc NixOS 配置

从 Arch Linux + Hyprland/quickshell-ii 迁移而来,新桌面: **niri + quickshell**。
Flake + Home Manager 结构,所有用户级配置在 `home/`,系统级在 `modules/`。

## 目录结构

```
.
├── flake.nix                  # 入口,锁定 nixpkgs/home-manager/niri-flake
├── hosts/present-pc/
│   ├── configuration.nix      # 主机配置入口
│   └── hardware-configuration.nix  # 占位,安装时替换!
├── modules/                   # 系统级
│   ├── boot.nix               # GRUB + os-prober + linux-zen
│   ├── network.nix            # NetworkManager + Bluetooth + Tailscale + SSH
│   ├── audio.nix              # PipeWire
│   ├── graphics.nix           # AMD RX 9070 (mesa + ROCm)
│   ├── desktop.nix            # niri + sddm (X11/Candy) + portal + Qt6 依赖 + 多屏 xrandr
│   ├── input-method.nix       # fcitx5 + rime
│   ├── keyd.nix               # 内核层 tap-hold: LeftMeta tap → F13 (Win 弹 launcher)
│   ├── fonts.nix              # CJK + Nerd Font
│   ├── locale.nix             # zh_CN.UTF-8 + Asia/Shanghai (LC_MESSAGES 跟随中文)
│   ├── services.nix           # docker / waydroid / sunshine / flatpak
│   ├── snapshots.nix          # btrbk 自动快照
│   ├── users.nix              # present 用户 + fish
│   ├── packages.nix           # 系统级包
│   └── nix.nix                # flakes / GC / 镜像
└── home/                      # home-manager
    ├── home.nix
    ├── shell.nix              # fish + starship + atuin + zoxide + fzf
    ├── kitty.nix
    ├── git.nix
    ├── niri.nix               # niri 全部 settings: outputs/键位/spawn/window-rules + DMS 集成
    ├── desktop.nix            # GTK/Qt 主题 + chromium/electron flags + rime custom.yaml
    ├── nvim.nix               # nixvim (LazyVim 风格)
    ├── yazi.nix               # programs.yazi 声明式
    ├── dev.nix                # rust/node/jdk21/python/typst/mdbook
    └── packages.nix           # 用户 CLI 包
```

## 首次安装步骤

**前提**: 现有 Arch 的 btrfs 布局只有 `@` (root) 和 `@home`。`@home` 全保留,`@`
要替换为 NixOS,并新建 `@nix` 和 `@snapshots`。

### 1. 装机前 (在 Arch 里)

- 备份关键数据 (尤其 ssh keys、gpg、未提交的 dev 项目)
- 把本仓库 push 到 GitHub,U 盘里 NixOS 安装环境再 clone
- 记录: `~/.dotfiles/` bare repo 仍在 `@home`,迁移后是否继续用看个人

### 2. 用 NixOS minimal ISO 启动 → 调整子卷

```bash
sudo mkdir -p /mnt-top
sudo mount -o subvolid=5 /dev/nvme1n1p3 /mnt-top
sudo btrfs subvol list /mnt-top   # 确认 @ + @home

# (可选) 备份 Arch 的 @,装完 NixOS 没问题再删
sudo btrfs subvol snapshot -r /mnt-top/@ /mnt-top/@arch-backup

sudo btrfs subvol delete /mnt-top/@
sudo btrfs subvol create /mnt-top/@
sudo btrfs subvol create /mnt-top/@nix
sudo btrfs subvol create /mnt-top/@snapshots
sudo umount /mnt-top
```

### 3. 按目标布局挂载

```bash
MOPT="compress=zstd:3,noatime,ssd,space_cache=v2,discard=async"
sudo mount -o "$MOPT,subvol=@"          /dev/nvme1n1p3 /mnt
sudo mkdir -p /mnt/{boot,home,nix,snapshots}
sudo mount -o "$MOPT,subvol=@home"      /dev/nvme1n1p3 /mnt/home
sudo mount -o "$MOPT,subvol=@nix"       /dev/nvme1n1p3 /mnt/nix
sudo mount -o "$MOPT,subvol=@snapshots" /dev/nvme1n1p3 /mnt/snapshots
sudo mount                              /dev/nvme1n1p1 /mnt/boot
```

### 4. 生成 hardware-configuration.nix

```bash
sudo nixos-generate-config --root /mnt --dir /tmp/nixcfg
diff /tmp/nixcfg/hardware-configuration.nix \
     /mnt/home/present/nix_migrate/hosts/present-pc/hardware-configuration.nix
# 把 boot.initrd.availableKernelModules / boot.kernelModules 等
# 缺失项合并进仓库版本 (UUID/subvol 我已写好,不要被覆盖)
```

### 5. 装机

```bash
sudo nixos-install --flake /mnt/home/present/nix_migrate#present-pc
sudo nixos-enter --root /mnt -c 'passwd present'
reboot
```

### 6. 进入 NixOS

```fish
sudo nixos-rebuild switch --flake ~/nix_migrate#present-pc
sudo btrbk run                          # 第一轮快照
sudo btrfs subvol delete /snapshots/@arch-backup  # 确认无事后清理
```

## 后续日常

home-manager 作为 NixOS 模块整合,只需一条命令同步系统+用户。推荐用 `nh` 包装:

```fish
# 重建系统 (推荐, nh 自带 diff + nom 输出)
nh os switch ~/nix_migrate

# 只 build 不切换 (验证 eval / 编译)
nh os build ~/nix_migrate

# 更新 flake input 后切换
nix flake update ~/nix_migrate
nh os switch ~/nix_migrate

# 原生命令 (备用)
sudo nixos-rebuild switch --flake ~/nix_migrate#present-pc
```

**注意**: flakes 只看 git-tracked 文件 —— 新建的 .nix 文件 build 前必须先 `git add`,
否则 `nh` 会报 `Path 'xxx.nix' not tracked by Git`。不需要 commit。

## 待办 / 需要本人补全

### 高优先级 (新机器)
- [ ] **替换 hardware-configuration.nix** (nixos-generate-config 输出)
- [ ] 检查 `hosts/present-pc/hardware-configuration.nix` 中 btrfs `subvol=` 选项
- [ ] **DMS 壁纸**: 由 DankMaterialShell 自身管理,首次进桌面后在 DMS 设置面板里挑
- [ ] **rime schema 部署**: 切换 schema 或改 `*.custom.yaml` 后:
  ```fish
  rm -rf ~/.local/share/fcitx5/rime/build && fcitx5 -r
  ```
  当前默认: 小鹤双拼简体 (double_pinyin_flypy, simplification reset=1)。
  词库 (rime-ice 等) 按需自行 clone,nixpkgs 的 rime-data 已自带 double_pinyin_flypy。

### Neovim — nixvim 声明式

`home/nvim.nix` 用 [nixvim](https://github.com/nix-community/nixvim) 全声明式接管,
LazyVim 风格起步配置: tokyonight 主题 / neo-tree / telescope / lualine / bufferline /
treesitter / gitsigns / which-key / mini.* / flash / trouble / noice / persistence /
完整 LSP (rust/ts/python/go/lua/nix/...) / cmp 自动补全 / conform 格式化 / nvim-lint。

迭代时直接编辑 `home/nvim.nix` 后 `nixos-rebuild switch`,无需自管 lazy.nvim。
原 `~/.config/nvim` 不再生效 (但因为 home-manager `backupFileExtension="hm-backup"`,
首次切换时会被改名为 `nvim.hm-backup` 而不是删除)。

### Yazi — programs.yazi 声明式

`home/yazi.nix` 通过 home-manager 模块管理 settings/keymap/plugins。
插件来自 `pkgs.yaziPlugins.*` (git / smart-enter / full-border 已加),按需添加。

### 中文软件
全部在 nixpkgs 里,已写进 `home/desktop.nix`:
- `wpsoffice-cn` — WPS 中国版
- `qq` — 即 linuxqq,腾讯 QQ
- `feishu` — 飞书 (撰写时 7.62.9)

flatpak 模块仍开着 (`services.flatpak.enable`),备用于 nixpkgs 没及时跟版本时手动 `flatpak install`。

### Quickshell — DankMaterialShell (DMS)

不再用 illogical-impulse,改用 [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell):
- 官方支持 niri,通过 flake input `dms` + home-manager 模块接入
- 自动注入 niri 键位 (Mod+Space spotlight / Mod+V 剪贴板 / Mod+N 通知 等)
- DMS 进程由 user systemd 服务跑 (`systemd.enable=true` + `enableSpawn=false`,
  避免 spawn-at-startup 又启一份导致两条 bar)
- 接管: bar / 动态主题 (matugen) / 通知中心 / spotlight / 剪贴板 / 设置 /
  电源菜单 / 系统监控 / 壁纸 / 音量亮度 OSD
- **不**接管: 锁屏定时 (用 swayidle 调 `dms ipc lock lock`)、键位/显示/光标/
  窗口规则 (这些由 home-manager 写到 niri config —— 见下面"分工"段)

**DMS 设置面板 vs home-manager 分工**

DMS 设置面板里"键盘快捷键 / 显示 / 光标主题 / 窗口规则"会提示
"找到配置文件,未导入" —— 那是它想接管 `~/.config/niri/config.kdl`,
但这个文件是 home-manager 写的 nix-store 只读 symlink,DMS 写不回去。
**约定**: 这四类全在 `home/niri.nix` 声明式管理,DMS 设置面板只当只读展示,
导入提示直接 Dismiss。

**自定义键位补充** (在 home/niri.nix 里手写,非 DMS 注入):
- `Mod+BackSpace` — DMS 电源菜单 (`dms ipc powermenu toggle`)
- `Mod+Alt+L`     — 锁屏 (`dms ipc lock lock`)
- `Win` 单点      — DMS spotlight (走 keyd: LeftMeta tap → F13 → xkb XF86Tools)
- `Mod+Ctrl+hjkl` — 屏幕间跳焦点; 加 `Shift` 把当前列搬过去
- `Mod+Shift+E`   — 退出 niri (回 SDDM)

### 输入 — keyd

niri 本身没有 tap-vs-hold 区分,需要在内核层做。`modules/keyd.nix`:

```
leftmeta = overload(meta, f13)
```

长按 LeftMeta 仍是 Super modifier (Mod 组合键照旧),单点发 KEY_F13。
F13 在默认 xkb keymap 里被解释成 `XF86Tools` keysym,所以 niri.nix 里
bind 的是 `XF86Tools` (不是 `F13`)。

调试: `sudo keyd monitor` 看实时事件。

### 显示 / 多屏

主屏 = `DP-1` (4K@240, scale 1.5),副屏 = `DP-2` (2560x1600@160, scale 1.5,
**90° 顶部朝左**,摆主屏左侧)。配置在 `home/niri.nix` 的 `outputs.*`。

niri 没有 "primary monitor" 字段,启动焦点按 connector 注册顺序 ——
spawn-at-startup 加了 `sleep 1 && niri msg action focus-monitor DP-1` 强制钉主屏。

SDDM (X11) 的 greeter 走 Qt primaryScreen,但 amdgpu 默认把 DP-2 排到 (0,0) ——
`modules/desktop.nix` 的 `setupCommands` 在 Xsetup 阶段直接 `--off DP-2` +
`--primary --auto DP-1`,让 greeter 只能落主屏,登录后 niri 自己重新点亮副屏。

### 开发
- Rust 用 `rustup` 管理 (避开 nixpkgs 版本切换的麻烦)
- Python 全局环境含 pip/uv/poetry; 项目内推荐 direnv + flake.nix
- Java: 仅装 jdk21 (gradle/kotlin 都已支持);需要 jdk17 的旧项目自行 nix-shell

### Btrfs 快照 (替代 Timeshift)

由 `modules/snapshots.nix` 中的 `services.btrbk` 自动管理。

**保留策略**:
- `@home`: 24 小时 + 7 日 + 4 周 + 3 月
- `@`:     12 小时 + 3 日 (系统层主要靠 generations,快照只是辅助)
- `@nix`:  不快照

**手动操作**:
```fish
# 立即跑一次 (不等 timer)
sudo btrbk run

# 列快照
sudo btrbk list snapshots

# 看实际占用 (考虑 CoW 共享)
sudo btdu /

# 看压缩比
sudo compsize /home

# rebuild 前手动快一发
sudo btrfs subvolume snapshot -r /@home /snapshots/@home/manual-(date +%Y%m%d-%H%M)
```

**恢复文件**: 直接 `cp /snapshots/@home/<时间>/relative/path ~/`,只读快照不会被误删。

**整盘还原**: 引导进 NixOS rescue → 重命名当前 `@home` → 把目标快照 `btrfs sub snapshot` 成新 `@home` → reboot。NixOS 系统本身坏了不用动快照,**直接在 GRUB 选 older generation** 即可。

**异机备份** (可选): 在 `services.btrbk.instances.local.settings` 里加
```nix
target."ssh://backup.lan/mnt/btrfs/backup" = {};
```
btrbk 会用 incremental send 推送增量。

### 双启动 NTFS 挂载
NTFS 分区 (nvme0n1p2/p4) **不在自动挂载列表**,按需手动添加到
`hosts/present-pc/hardware-configuration.nix` 或用 udisks2 临时挂载。

### 暂未迁移的包/功能 (可按需手动加)
- 游戏: steam / lutris / wine / ryujinx
- 媒体: jellyfin-media-player / netease-cloud-music
- 仿真: torzu / yuzu
- IDE: jetbrains-toolbox (建议直接用 nix-shell 或下载 tar)
- VSCode: 已加,见 `home/dev.nix`

## 移除/合并的旧包
- `illogical-impulse-*` 全套: 与 hyprland 绑定,niri 下重写
- `hyprland` / `hyprlock` / `hyprtoolkit` / `swaylock-effects`: 不再使用
- `oh-my-zsh` / `zsh-theme-powerlevel10k`: 改用 fish + starship 单一 shell
- `paru` / `yay`: NixOS 包管理替代
- `grub-btrfs` / `timeshift`: 用 btrfs snapshot + nh/nixos generations 替代
- `nvm`: 用 nixpkgs 中的 `nodejs_22` 或 direnv 项目级管理
