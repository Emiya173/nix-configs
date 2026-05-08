#!/usr/bin/env bash
# 在 Arch (或任何装了 nix daemon 的非 NixOS 系统) 上验证本 flake
# 前置:
#   sudo pacman -S nix
#   sudo systemctl enable --now nix-daemon
#   sudo usermod -aG nix-users $USER  # 重登 shell

set -euo pipefail

cd "$(dirname "$0")/.."

NIX_FLAGS=(--extra-experimental-features 'nix-command flakes')

echo "==> nix flake check (eval 全部 outputs / 检查所有 module 能 evaluate)"
nix "${NIX_FLAGS[@]}" flake check --no-build

echo "==> 单独 eval 系统配置 (确认 hosts/present-pc 整套能 build 出 derivation)"
nix "${NIX_FLAGS[@]}" eval ".#nixosConfigurations.present-pc.config.system.build.toplevel.drvPath" --raw
echo

echo "==> 列出全部 systemPackages (抽查)"
nix "${NIX_FLAGS[@]}" eval ".#nixosConfigurations.present-pc.config.environment.systemPackages" \
  --apply 'pkgs: builtins.length pkgs' \
  | xargs -I {} echo "    systemPackages count: {}"

echo
echo "==> 全部检查通过"
