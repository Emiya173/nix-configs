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
│   ├── desktop.nix            # niri + sddm + portal + Qt6/quickshell 依赖
│   ├── input-method.nix       # fcitx5 + rime
│   ├── fonts.nix              # CJK + Nerd Font
│   ├── locale.nix             # zh_CN.UTF-8 + Asia/Shanghai
│   ├── services.nix           # docker / waydroid / sunshine / flatpak
│   ├── users.nix              # present 用户 + fish
│   ├── packages.nix           # 系统级包
│   └── nix.nix                # flakes / GC / 镜像
└── home/                      # home-manager
    ├── home.nix
    ├── shell.nix              # fish + starship + atuin + zoxide + fzf
    ├── kitty.nix
    ├── git.nix
    ├── desktop.nix            # niri 配置 + GTK/Qt + 桌面工具
    ├── dev.nix                # rust/node/jdk/python/typst/mdbook
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

```fish
# 重建系统
sudo nixos-rebuild switch --flake ~/nix_migrate#present-pc

# 更新输入
nix flake update ~/nix_migrate
sudo nixos-rebuild switch --flake ~/nix_migrate#present-pc

# 仅更新 home-manager (作为 NixOS 模块,通常跟随 system)
# 不需要单独运行
```

## 待办 / 需要本人补全

### 高优先级
- [ ] **替换 hardware-configuration.nix** (nixos-generate-config 输出)
- [ ] 检查 `hosts/present-pc/hardware-configuration.nix` 中 btrfs `subvol=` 选项
- [ ] **niri 壁纸路径** `home/desktop.nix` 的 swaybg 默认指向 `~/Pictures/wallpaper.jpg`
- [ ] **rime 词库** 安装后手动:
  ```
  git clone https://github.com/iDvel/rime-ice ~/.local/share/fcitx5/rime
  ```
- [ ] 确认 sddm 是否能正常启动 niri 会话 (sddm + wayland session)

### 中文软件
- `wpsoffice-cn`: 已加入 `home/desktop.nix`
- `linuxqq` / `feishu`: nixpkgs 不稳定,推荐 flatpak:
  ```
  flatpak install flathub com.tencent.QQ
  flatpak install flathub com.feishu.Feishu
  ```
  (services.flatpak.enable 已开启)

### Quickshell
- 已装 quickshell + Qt6 全套依赖
- ii 配置依赖 hyprland IPC,**niri 不可直接复用**
- 待自写: bar / launcher / notification / lock 适配 niri (可参考 `niri msg` 输出)
- 临时方案: `home.packages` 里有 `fuzzel` 作 launcher,后续替换为自己 quickshell 版

### 开发
- Rust 用 `rustup` 管理 (避开 nixpkgs 版本切换的麻烦)
- Python 全局环境含 pip/uv/poetry; 项目内推荐 direnv + flake.nix
- Java: jdk17 + jdk21 共存,环境变量 `JAVA_HOME` 默认指向 jdk21,可在 shell 里 override

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
