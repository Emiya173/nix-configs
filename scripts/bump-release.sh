#!/usr/bin/env bash
# 升 NixOS release 的单点入口: ./scripts/bump-release.sh 26.11
#
# flake input 的 url 必须是字面量 (flakes 静态解析 inputs,不能引用变量),
# 所以 nixpkgs / home-manager / nixvim 三处的版本号没法在 Nix 层收敛,
# 这里用 sed 一把全改 (只动 url 行,不碰注释里的版本号,比如 michi-ocr 的说明)。

set -euo pipefail

new="${1:?用法: bump-release.sh <版本, 如 26.11>}"
cd "$(dirname "$0")/.."

old=$(grep -oP 'url = "github:NixOS/nixpkgs/nixos-\K[0-9]{2}\.[0-9]{2}' flake.nix)
if [ "$old" = "$new" ]; then
  echo "flake.nix 已经是 $new,无需修改"
  exit 0
fi

old_esc="${old//./\\.}"
sed -i -E "/url = \"github:/ s/${old_esc}/${new}/g" flake.nix

echo "==> flake.nix: ${old} -> ${new},受影响的 input:"
grep -n "$new" flake.nix | grep 'url ='

echo "==> 更新 flake.lock"
nix flake update nixpkgs home-manager nixvim

echo "==> 完成。下一步:"
echo "    nh os build ~/nix_migrate    # 先验证"
echo "    nh os switch ~/nix_migrate   # 再切换"
