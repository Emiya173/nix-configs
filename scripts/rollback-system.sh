#!/usr/bin/env bash
# Run from the checkout or through the installed nixos-rollback command.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rollback_user=${rollback_user:-$(id -un)}
rollback_home=${rollback_home:-$(getent passwd "$rollback_user" | cut -d: -f6)}
rollback_manifest=${rollback_manifest:-"$script_dir/../assets/home-manager-files/$(hostname).json"}
rollback_migration=${rollback_migration:-"$script_dir/migrate-home-manager.py"}

generation=
apply=false
while (( $# > 0 )); do
  case "$1" in
    --to|-t)
      if (( $# < 2 )) || [[ ! $2 =~ ^[0-9]+$ ]]; then
        echo '--to requires a generation number' >&2
        exit 2
      fi
      generation=$2
      shift 2
      ;;
    --apply) apply=true; shift ;;
    --help|-h)
      echo 'Usage: nixos-rollback [--to GENERATION] [--apply]'
      echo 'Previews the target and home conflicts by default. --apply preserves conflicts before activation.'
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ $(id -un) != "$rollback_user" || $(id -u) == 0 ]]; then
  echo "Run as $rollback_user, without sudo on this command." >&2
  exit 1
fi
current_profile=$(readlink /nix/var/nix/profiles/system)
if [[ ! $current_profile =~ system-([0-9]+)-link$ ]]; then
  echo 'Cannot identify the selected system generation.' >&2
  exit 1
fi
current_generation=${BASH_REMATCH[1]}
if [[ -z $generation ]]; then
  generation=0
  for profile in /nix/var/nix/profiles/system-*-link; do
    [[ $profile =~ system-([0-9]+)-link$ ]] || continue
    number=${BASH_REMATCH[1]}
    if (( number < current_generation && number > generation )); then
      generation=$number
    fi
  done
fi
if ! target=$(readlink -e "/nix/var/nix/profiles/system-$generation-link") ||
   [[ ! -x "$target/bin/switch-to-configuration" ]]; then
  echo "Generation $generation is unavailable." >&2
  exit 1
fi

prepare=(python3 "$rollback_migration" --home "$rollback_home"
  --manifest "$rollback_manifest" --user "$rollback_user" --rollback-system "$target")
printf 'Target generation: %s\n' "$generation"
"${prepare[@]}"
nvd diff /run/current-system "$target"
if ! $apply; then
  printf 'To apply, rerun this command with: --to %s --apply\n' "$generation"
  exit 0
fi

# Authenticate before touching home files. Existing .hm-backup files remain
# intact: conflicting live files get their own unique, audited backup instead.
sudo -v
if [[ $(readlink /nix/var/nix/profiles/system) != "$current_profile" ||
      $(readlink -e "/nix/var/nix/profiles/system-$generation-link") != "$target" ]]; then
  echo 'System profiles changed during preview; rerun the command.' >&2
  exit 1
fi
"${prepare[@]}" --apply
if [[ $(readlink -e /nix/var/nix/profiles/system) == "$target" ]]; then
  # Complete a partially failed activation of the already-selected generation.
  sudo -n "$target/bin/switch-to-configuration" switch
else
  nh os rollback --to "$generation"
fi
[[ $(readlink -e /run/current-system) == "$target" ]]
[[ $(readlink -e /nix/var/nix/profiles/system) == "$target" ]]
if [[ -e "$target/etc/systemd/system/home-manager-$rollback_user.service" ]]; then
  systemctl is-active "home-manager-$rollback_user.service"
fi
