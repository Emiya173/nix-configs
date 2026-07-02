{
  description = "present-pc NixOS configuration (migrated from Arch)";

  inputs = {
    # 主包源走 stable。升 release 用 ./scripts/bump-release.sh <新版本>,
    # 会一把改掉这里 + home-manager release-* + nixvim nixos-* 并更新 lock
    # (flake input url 必须是字面量,版本号没法在 Nix 层单点定义)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # unstable 精选通道: 只有下方 overlay 点名的包 (目前仅 claude-code) 从这里取;
    # 同时以 pkgs.unstable.* 暴露整棵,临时要新包时写 unstable.foo 即可
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # michi-ocr: 自有仓库,经 flake.lock 锁定即可复现。不 follows nixpkgs ——
    # 它刻意 pin nixos-26.05,跟到 unstable 反而可能踩 GTK/torch 接口变化。
    michi-ocr.url = "github:Emiya173/michi-ocr";
  };

  outputs = { self, nixpkgs, home-manager, niri, dms, nixvim, ... }@inputs:
    let
      system = "x86_64-linux";
      hostName = "present-pc";
      userName = "present";
    in
    {
      nixosConfigurations.${hostName} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs userName hostName; };
        modules = [
          ./hosts/${hostName}/configuration.nix
          niri.nixosModules.niri
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs userName; };
            home-manager.users.${userName} = import ./home/home.nix;
            home-manager.backupFileExtension = "hm-backup";
            # 注意:dms.homeModules.niri 自己 import 了 niri.homeModules.niri,
            # 这里再加 niri.homeModules.niri 会让 programs.niri.finalConfig 双重声明
            home-manager.sharedModules = [
              dms.homeModules.dank-material-shell
              dms.homeModules.niri
              nixvim.homeModules.nixvim
              inputs.michi-ocr.homeManagerModules.default
            ];
          }
        ];
      };
    };
}
