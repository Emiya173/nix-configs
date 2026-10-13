{ userName }:
let
  home = "/home/${userName}";
in
{
  inherit home;
  repository = "${home}/mirgate/nix-configs";
  voidmaker = "${home}/dev/VoidMaker";
}
