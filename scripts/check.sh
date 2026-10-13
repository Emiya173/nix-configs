#!/usr/bin/env bash
# Layers: evaluation, build-time checks, critical packages, complete system.
set -euo pipefail
cd "$(dirname "$0")/.."

NIX_FLAGS=(--extra-experimental-features 'nix-command flakes')
# Include new host modules before staging, without changing the Git index.
FLAKE="path:$PWD"
host=present-pc

usage() {
  echo "Usage: $0 [eval|checks|packages [package ...]|system [present-pc|arch-pc]|all [present-pc|arch-pc]]" >&2
}

mode=${1-eval}
if (( $# > 0 )); then
  shift
fi

case "$mode" in
  packages)
    for package in "$@"; do
      case "$package" in
        qq|codex|baidunetdisk|fastfetch|xlog|dingtalk|chatgpt-desktop|dae-subscription) ;;
        *)
          echo "Unknown maintained package: $package" >&2
          usage
          exit 2
          ;;
      esac
    done
    ;;
  system|all)
    if (( $# > 1 )); then usage; exit 2; fi
    host=${1-present-pc}
    case "$host" in
      present-pc|arch-pc) ;;
      *) echo "Unknown host: $host" >&2; usage; exit 2 ;;
    esac
    ;;
  eval|checks)
    if (( $# > 0 )); then
      echo "The '$mode' command does not accept extra arguments." >&2
      usage
      exit 2
    fi
    ;;
  *)
    echo "Unknown command: $mode" >&2
    usage
    exit 2
    ;;
esac

check_eval() {
  echo "==> Evaluate locked flake outputs"
  nix "${NIX_FLAGS[@]}" flake check "$FLAKE" --no-build --no-update-lock-file
  local target
  for target in present-pc arch-pc; do
    echo "==> Evaluate complete host: $target"
    nix "${NIX_FLAGS[@]}" eval --no-update-lock-file \
      "$FLAKE#nixosConfigurations.$target.config.system.build.toplevel.drvPath" --raw
    echo
  done
}

check_builds() {
  echo "==> Build checks (script lint + Nix formatting)"
  nix "${NIX_FLAGS[@]}" flake check "$FLAKE" --no-update-lock-file
}

check_packages() {
  local -a packages=("$@") targets=()
  local package
  if (( ${#packages[@]} == 0 )); then
    packages=(qq codex baidunetdisk fastfetch xlog dingtalk chatgpt-desktop dae-subscription)
  fi
  for package in "${packages[@]}"; do
    targets+=("$FLAKE#$package")
  done
  echo "==> Build maintained packages: ${packages[*]}"
  nix "${NIX_FLAGS[@]}" build --no-link --no-update-lock-file \
    "${targets[@]}"
}

check_system() {
  echo "==> Build full system without activation: $host"
  nix "${NIX_FLAGS[@]}" build --no-link --no-update-lock-file \
    "$FLAKE#nixosConfigurations.$host.config.system.build.toplevel"
}

case "$mode" in
  eval) check_eval ;;
  checks) check_builds ;;
  packages) check_packages "$@" ;;
  system) check_system ;;
  all) check_eval; check_builds; check_packages; check_system ;;
esac
