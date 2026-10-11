{ userName }:

let
  home = "/home/${userName}";
in
{
  inherit home;
  # 使用运行时字符串，避免将可变开发目录复制到 Nix store。
  repository = "${home}/nix_migrate";
  voidmaker = "${home}/dev/VoidMaker";
}
