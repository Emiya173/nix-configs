# Repository Guidelines

## Project Structure & Module Organization

This repository defines the `present-pc` NixOS system as a flake. Keep machine
assembly in `hosts/present-pc/`, reusable system configuration in `modules/`,
and user-scoped Home Manager configuration in `home/`. Custom derivations live
in `packages/` and are exposed through `overlays/`. Static boot, login, and
Fastfetch resources belong in `assets/`. Maintenance and validation helpers are
in `scripts/`.

Add new system modules to `hosts/present-pc/configuration.nix`; add new Home
Manager modules to `home/home.nix`. Keep hardware-specific values in
`hosts/present-pc/hardware-configuration.nix`.

## Build, Test, and Development Commands

- `./scripts/check.sh` evaluates all flake outputs and the complete host
  configuration without building it.
- `nix flake check --no-build` performs the core evaluation check directly.
- `nh os build .` builds the system closure without activating it.
- `nh os switch .` builds and activates the configuration; review the diff
  before confirming privileged changes.
- `nix build .#codex` builds an individual exported package.
- `nixfmt <file.nix>` formats Nix sources using RFC-style formatting.
- `./scripts/bump-release.sh 26.11` updates the coordinated stable release
  inputs and lock file.

Flakes only include Git-tracked files, so stage newly referenced files before
evaluation.

## Coding Style & Naming Conventions

Use two-space indentation and let `nixfmt` determine layout. Prefer small,
single-purpose modules and declarative option assignments over shell setup.
Name files and attributes in lowercase kebab-case, following existing examples
such as `input-method.nix` and `hardware-configuration.nix`. Pass shared values
through module arguments or `specialArgs`; avoid hidden mutable state. Comments
should explain constraints or non-obvious decisions, not restate the code.

## Testing Guidelines

There is no separate unit-test suite. Every change must pass
`./scripts/check.sh`; package changes should also pass their targeted
`nix build`. For changes affecting services, graphics, boot, or the desktop,
run `nh os build .` before switching. Do not commit generated `result` links.

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
