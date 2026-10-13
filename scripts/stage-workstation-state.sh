#!/usr/bin/env bash
# Stage selected runtime state into an already mounted NixOS root.
# Never partition, create subvolumes, delete data or start services here.
set -euo pipefail
if [[ $EUID -ne 0 || $# -ne 1 ]]; then
  echo "Usage: sudo $0 /mnt" >&2
  exit 1
fi
target=$(realpath -- "$1")
[[ "$target" != / && -d "$target" ]] || { echo 'Refusing the running root or a missing target' >&2; exit 1; }
mountpoint -q -- "$target" || { echo 'Target must be a mounted installation root' >&2; exit 1; }
[[ $(findmnt -n -o FSROOT --target "$target") == /@nixos ]] || { echo 'Target must mount @nixos' >&2; exit 1; }
umask 077
install -d -m 700 "$target/var/lib/nixos-secrets" "$target/etc/dae" "$target/etc/hysteria" "$target/etc/NetworkManager/system-connections" "$target/var/lib/dae-subscription-config"
install -m 600 /etc/dae/config.dae "$target/etc/dae/config.dae"
# Preserve the full YAML, including the QUIC field omitted by the audit summary.
install -m 600 /etc/hysteria/client.yaml "$target/etc/hysteria/client.yaml"
install -m 600 /etc/hysteria/vps-reverse.key "$target/etc/hysteria/vps-reverse.key"
install -m 644 /etc/hysteria/known_hosts "$target/etc/hysteria/known_hosts"
for profile in /etc/NetworkManager/system-connections/*; do
  [[ -f "$profile" ]] || continue
  install -m 600 "$profile" "$target/etc/NetworkManager/system-connections/$(basename "$profile")"
done
install -d -m 755 "$target/etc/ssh"
for hostkey in /etc/ssh/ssh_host_*; do
  [[ -f "$hostkey" ]] || continue
  mode=600
  [[ "$hostkey" == *.pub ]] && mode=644
  install -m "$mode" "$hostkey" "$target/etc/ssh/$(basename "$hostkey")"
done
password_hash=$(getent shadow present | cut -d: -f2)
[[ -n "$password_hash" && "$password_hash" != '!'* && "$password_hash" != '*'* ]] || { echo 'No usable login password hash for present' >&2; exit 1; }
printf '%s\n' "$password_hash" > "$target/var/lib/nixos-secrets/present-password-hash"
unset password_hash
source_file=/var/lib/dae-subscription-config/upstream-url
if [[ -s "$source_file" ]]; then
  install -m 600 "$source_file" "$target/var/lib/dae-subscription-config/upstream-url"
else
  [[ -t 0 ]] || { echo 'Subscription source missing; rerun in an interactive terminal' >&2; exit 1; }
  read -r -s -p 'Upstream subscription URL (hidden): ' subscription_url
  printf '\n'
  [[ "$subscription_url" == https://* || "$subscription_url" == http://* ]] || { echo 'Expected an HTTP(S) URL' >&2; exit 1; }
  printf '%s\n' "$subscription_url" > "$target/var/lib/dae-subscription-config/upstream-url"
  unset subscription_url
fi
chmod 600 "$target/var/lib/nixos-secrets/present-password-hash" "$target/var/lib/dae-subscription-config/upstream-url"
printf '%s\n' 'Selected network state, SSH identity and login hash staged. User/work data and Docker exports are separate.'
