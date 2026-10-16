#!/usr/bin/env bash
# 升 NixOS release 的单点入口: ./scripts/bump-release.sh 26.11
#
# flake input 的 url 必须是字面量 (flakes 静态解析 inputs,不能引用变量),
# 所以 nixpkgs / nixvim 两处的版本号没法在 Nix 层收敛,
# 这里只更新这两个 input 的 release URL,不碰其他 input 和注释。

set -euo pipefail

if [[ $# -ne 1 || ! ${1-} =~ ^[0-9]{2}\.(05|11)$ ]]; then
  echo "用法: $0 <版本, 如 26.11>; 仅接受一个 YY.05 或 YY.11 版本号" >&2
  exit 2
fi

new="$1"
cd "$(dirname "$0")/.."

old=$(sed -nE 's/^[[:space:]]*nixpkgs\.url = "github:NixOS\/nixpkgs\/nixos-([0-9]{2}\.[0-9]{2})";.*/\1/p' flake.nix)
if [[ ! $old =~ ^[0-9]{2}\.(05|11)$ ]]; then
  echo "无法唯一识别 flake.nix 中 nixpkgs 的 stable release URL,未修改文件" >&2
  exit 1
fi

if [ "$old" = "$new" ]; then
  echo "==> nixpkgs URL 已经是 $new,继续同步两个 release URL 和 flake.lock"
else
  echo "==> release URL: ${old} -> ${new} (nixpkgs / nixvim)"
fi

sed -i -E \
  -e "/^[[:space:]]*nixpkgs\\.url = / s|(\"github:NixOS/nixpkgs/nixos-)[0-9]{2}\\.[0-9]{2}(\";)|\\1${new}\\2|" \
  -e "/^[[:space:]]*nixvim = \\{/,/^[[:space:]]*\\};/ s|(^[[:space:]]*url = \"github:nix-community/nixvim/nixos-)[0-9]{2}\\.[0-9]{2}(\";)|\\1${new}\\2|" \
  flake.nix

echo "==> 更新 flake.lock"
if nix flake update nixpkgs nixvim; then
  echo "==> 检查更新后的配置"
else
  update_status=$?
  echo "更新 flake.lock 失败; release URL 已保留。修复错误后可用相同版本重试: ./scripts/bump-release.sh $new" >&2
  exit "$update_status"
fi

if ./scripts/check.sh; then
  echo "==> 完成。在本仓库目录执行:"
else
  check_status=$?
  echo "配置求值检查失败; 请检查 flake.nix / flake.lock 的差异并修复后再构建" >&2
  exit "$check_status"
fi

echo "    nh os build .    # 先验证"
echo "    nh os switch .   # 再切换"
