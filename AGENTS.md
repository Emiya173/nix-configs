# Repository Guidelines

## Project Structure & Module Organization

This repository defines multiple NixOS hosts as a flake. Keep machine assembly
in `hosts/<hostname>/` and reusable NixOS configuration in `modules/`. Shared
user environment modules live in `modules/user/`, with `default.nix` as their
entry point. Custom derivations live in `packages/` and are exposed through
`overlays/`. Static boot, login, and
Fastfetch resources belong in `assets/`. Maintenance and validation helpers are
in `scripts/`.

Add host-specific system settings to `hosts/<hostname>/configuration.nix`.
Put host-specific applications, shell overrides, and user services in
`hosts/<hostname>/user.nix`, imported explicitly by that host's system entry.
Keep hardware-specific values in each host's `hardware-configuration.nix`.

Prefer native NixOS modules, then `nix-wrapper-modules` for configured packages,
and Hjem for the remaining fixed-location links. `modules/user/wrappers.nix`
handles Kitty/Fastfetch/btop; `modules/user/niri.nix` preserves niri-flake's
settings serializer and supplies the wrapped compositor. Keep personal Git
identity in the user's Hjem file, not the system Git config. Leave DMS settings,
GTK CSS, Qt color files, and Kitty's dynamic theme files writable. Do not
reintroduce Home Manager or add another application-module abstraction layer.

## Build, Test, and Development Commands

- `./scripts/check.sh` evaluates all flake outputs and the complete host
  configuration without building it.
- `nix flake check --no-build` performs the core evaluation check directly.
- `nh os build .` builds the system closure without activating it.
- `nh os switch .` builds and activates the configuration; review the diff
  before confirming privileged changes.
- `nix build .#nixosConfigurations.present-pc.pkgs.codex` builds Codex from the
  host package set.
- `nixfmt <file.nix>` formats Nix sources using RFC-style formatting.
- `./scripts/bump-release.sh 26.11` updates the coordinated stable release
  inputs and lock file.

Git-backed flake commands only include tracked files, so stage newly referenced
files before switching; a commit is not required. `scripts/check.sh` uses a
`path:` flake and can evaluate new files before staging.

## Coding Style & Naming Conventions

Use two-space indentation and let `nixfmt` determine layout. Prefer small,
single-purpose modules and declarative option assignments over shell setup.
Name files and attributes in lowercase kebab-case, following existing examples
such as `input-method.nix` and `hardware-configuration.nix`. Pass shared values
through module arguments or `specialArgs`; avoid hidden mutable state. Comments
should explain constraints or non-obvious decisions, not restate the code.

## Testing Guidelines

Subscription recovery and privacy tests live in `tests/test_subscription.py`.
Legacy HM link migration tests live in `tests/test_home_migration.py`; run them
only against disposable homes under `/tmp`, never against the real home. Both
run through flake checks. The frozen per-host allowlists under
`assets/home-manager-files/` describe the previous HM deployment; do not
regenerate them from the new Hjem configuration. A new host without HM history
still needs a version 1 manifest with an empty `targets` list, since
`modules/user/home.nix` selects the manifest by hostname. Every change must pass
`./scripts/check.sh`; package changes should also pass their targeted
`nix build`. For changes affecting services, graphics, boot, or the desktop,
build the affected host with `./scripts/check.sh system <hostname>` before
switching. For shared desktop or user-environment changes, build both hosts.
Do not commit generated `result` links.

`tests/check-greeter.sh` exercises the real launcher in a private headless
Wayland display. Keep its explicit Quickshell/Niri selection independent of
the user's desktop packages and test the full migration/rollback file handover.

## Commit & Pull Request Guidelines

Follow the repository’s Conventional Commit pattern:
`type(scope): concise description`, for example
`feat(niri): add window rule` or `fix(lazygit): update pager schema`. Keep each
commit focused and include `flake.lock` only when inputs changed. Pull requests
should explain the intent, list validation commands, call out activation or
rollback risks, and include screenshots only for visible desktop/theme changes.

## Security & Configuration Tips

Never commit credentials, private keys, or machine-local tokens. Inspect lock
file changes and fixed-output hashes carefully. Preserve `system.stateVersion`
unless performing a deliberate migration.

Legacy link handover is wired before Hjem activation in `modules/user/home.nix`.
Preserve the old system generations and `~/.local/state/home-manager-migration/`
backups until the user has verified the new session. Rolling back the system
can leave home-file collisions for the old HM activation, including existing
`*.hm-backup` files; do not promise automatic home restoration or delete those
files without inspecting the recorded paths and user changes.
Use `nixos-rollback` or `scripts/rollback-system.sh` when crossing the HM
migration boundary. The default previews; `--apply` preserves conflicting
files before switching. Do not replace this with force-overwriting home files.
