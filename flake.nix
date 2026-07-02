{
  description = "present-pc NixOS configuration (migrated from Arch)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # 仅用于把 claude-code 单独升到 unstable 最新版,不影响主 nixpkgs。
    # 主 nixpkgs 暂时 pin 在旧 commit,规避 fish 4.8.0 缺 create_manpage_completions.py
    # 导致 asciinema fish 补全构建失败的上游回归。等上游修好后可删掉本 input,
    # 把 claude-code overlay 一并去掉,恢复整体 flake update。
    nixpkgs-claude.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
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
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-flatpak 已经不再声明 nixpkgs input,follows 会触发 warning
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # michi-ocr: 自有仓库,经 flake.lock 锁定即可复现。不 follows nixpkgs ——
    # 它刻意 pin nixos-26.05,跟到 unstable 反而可能踩 GTK/torch 接口变化。
    michi-ocr.url = "github:Emiya173/michi-ocr";
  };

  outputs = { self, nixpkgs, home-manager, niri, dms, nixvim, nix-flatpak, ... }@inputs:
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
          # 只把 claude-code 一个包换成 unstable 最新版(见 nixpkgs-claude input)。
          # useGlobalPkgs = true,故此 overlay 同样作用于 home-manager 的包。
          {
            nixpkgs.overlays = [
              (final: prev: {
                claude-code = (import inputs.nixpkgs-claude {
                  inherit system;
                  config.allowUnfree = true;
                }).claude-code;
              })
            ];
          }
          niri.nixosModules.niri
          nix-flatpak.nixosModules.nix-flatpak
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
