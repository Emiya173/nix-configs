#!/usr/bin/env bash
# Layers: evaluation, build-time checks, critical packages, complete system.
set -euo pipefail
cd "$(dirname "$0")/.."

NIX_FLAGS=(--extra-experimental-features 'nix-command flakes')

check_eval() {
  echo "==> Evaluate locked flake outputs"
  nix "${NIX_FLAGS[@]}" flake check --no-build --no-update-lock-file
  nix "${NIX_FLAGS[@]}" eval --no-update-lock-file \
    .#nixosConfigurations.present-pc.config.system.build.toplevel.drvPath --raw
  echo
}

check_builds() {
  echo "==> Build checks (script lint)"
  nix "${NIX_FLAGS[@]}" flake check --no-update-lock-file
}

check_packages() {
  echo "==> Build QQ"
  nix "${NIX_FLAGS[@]}" build --no-link --no-update-lock-file \
    .#qq
}

check_system() {
  echo "==> Build full system without activation"
  nh os build . -- --no-update-lock-file
}

case "${1:-eval}" in
  eval) check_eval ;;
  checks) check_builds ;;
  packages) check_packages ;;
  system) check_system ;;
  all) check_eval; check_builds; check_packages; check_system ;;
  *) echo "Usage: $0 [eval|checks|packages|system|all]" >&2; exit 2 ;;
esac
