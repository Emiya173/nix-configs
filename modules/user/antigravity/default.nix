{ pkgs, userName, ... }:

let
  codexBridge = pkgs.writeShellScriptBin "codex-bridge" ''
    export CODEX_BIN="${pkgs.codex}/bin/codex"
    exec ${pkgs.nodejs_22}/bin/node ${./bridge.ts} "$@"
  '';
in
{
  users.users.${userName}.packages = [
    pkgs.antigravity-cli
    codexBridge
  ];

  hjem.users.${userName}.files.".gemini/config/skills/codex/SKILL.md".source = ./SKILL.md;
}
