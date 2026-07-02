{ inputs, ... }:

{
  # unstable 精选: 主系统跟 stable,点名的包例外走 nixpkgs-unstable。
  # flake 里 useGlobalPkgs = true,故此 overlay 同样作用于 home-manager 的包。
  nixpkgs.overlays = [
    (final: prev:
      let
        unstablePkgs = import inputs.nixpkgs-unstable {
          inherit (prev.stdenv.hostPlatform) system;
          config.allowUnfree = true;
        };
      in
      {
        inherit (unstablePkgs) claude-code;
        # 整棵挂在 pkgs.unstable 下,按需取新包 (unstable.foo)
        unstable = unstablePkgs;
      })
  ];
}
