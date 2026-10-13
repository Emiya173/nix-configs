#!/usr/bin/env bash
# Read-only checks against the prepared installation root.
set -euo pipefail
if [[ $# -ne 1 ]]; then echo "Usage: $0 /mnt" >&2; exit 1; fi
target=$(realpath -- "$1")
failed=0
check_file() {
  if [[ ! -s "$target$1" ]]; then printf 'MISSING %s\n' "$1"; failed=1; fi
}
for path in /etc/dae/config.dae /etc/hysteria/client.yaml /etc/hysteria/vps-reverse.key /etc/hysteria/known_hosts /var/lib/nixos-secrets/present-password-hash /var/lib/dae-subscription-config/upstream-url /home/present/container/easyconnect/docker-compose.yaml /home/present/.ssh/authorized_keys; do
  check_file "$path"
done
for pair in '/:@nixos' '/home:@home' '/nix:@nix' '/snapshots:@snapshots'; do
  path=${pair%:*}; expected=/${pair#*:}
  actual=$(findmnt -n -o FSROOT --mountpoint "$target$path" 2>/dev/null || true)
  [[ "$actual" == "$expected" ]] || { printf 'MOUNT %s expected %s, got %s\n' "$path" "$expected" "${actual:-unmounted}"; failed=1; }
done
if ! find "$target/etc/NetworkManager/system-connections" -maxdepth 1 -type f -name '*.nmconnection' -print -quit 2>/dev/null | grep -q .; then
  echo 'MISSING persistent NetworkManager profiles'; failed=1
fi
for path in /etc/hysteria/vps-reverse.key /var/lib/nixos-secrets/present-password-hash /var/lib/dae-subscription-config/upstream-url; do
  if [[ -f "$target$path" && $(stat -c %a "$target$path") != 600 ]]; then printf 'MODE %s must be 600\n' "$path"; failed=1; fi
done
[[ $failed -eq 0 ]] || exit 1
printf '%s\n' 'Required state and mounts are present. Verify independent backups and actual public-key login before install.'
