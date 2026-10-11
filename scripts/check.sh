#!/usr/bin/env bash
# Layers: evaluation, build-time checks, critical packages, complete system.
set -euo pipefail
cd "$(dirname "$0")/.."

NIX_FLAGS=(--extra-experimental-features 'nix-command flakes')

usage() {
  echo "Usage: $0 [eval|checks|packages [qq|codex|baidunetdisk ...]|system|all]" >&2
}

mode=${1-eval}
if (( $# > 0 )); then
  shift
fi

case "$mode" in
  packages)
    for package in "$@"; do
      case "$package" in
        qq|codex|baidunetdisk) ;;
        *)
          echo "Unknown package: $package (expected qq, codex, or baidunetdisk)" >&2
          usage
          exit 2
          ;;
      esac
    done
    ;;
  eval|checks|system|all)
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
  nix "${NIX_FLAGS[@]}" flake check --no-build --no-update-lock-file
  nix "${NIX_FLAGS[@]}" eval --no-update-lock-file \
    .#nixosConfigurations.present-pc.config.system.build.toplevel.drvPath --raw
  echo
}

check_builds() {
  echo "==> Build checks (script lint + Nix formatting)"
  nix "${NIX_FLAGS[@]}" flake check --no-update-lock-file
}

check_packages() {
  local -a packages=("$@") targets=()
  local package
  if (( ${#packages[@]} == 0 )); then
    packages=(qq codex baidunetdisk)
  fi
  for package in "${packages[@]}"; do
    targets+=(".#$package")
  done
  echo "==> Build maintained packages: ${packages[*]}"
  nix "${NIX_FLAGS[@]}" build --no-link --no-update-lock-file \
    "${targets[@]}"
}

check_system() {
  echo "==> Build full system without activation"
  nh os build . -- --no-update-lock-file
}

case "$mode" in
  eval) check_eval ;;
  checks) check_builds ;;
  packages) check_packages "$@" ;;
  system) check_system ;;
  all) check_eval; check_builds; check_packages; check_system ;;
esac
