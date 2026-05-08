{
  description = "present-pc NixOS configuration (migrated from Arch)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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

    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, niri, dms, nixvim, nix-flatpak, ... }@inputs:
    let
      system = "x86_64-linux";
      hostName = "present-pc";
      userName = "present";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations.${hostName} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs userName hostName; };
        modules = [
          ./hosts/${hostName}/configuration.nix
          niri.nixosModules.niri
          nix-flatpak.nixosModules.nix-flatpak
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.${userName} = import ./home/home.nix;
            home-manager.backupFileExtension = "hm-backup";
            # 注意:dms.homeModules.niri 自己 import 了 niri.homeModules.niri,
            # 这里再加 niri.homeModules.niri 会让 programs.niri.finalConfig 双重声明
            home-manager.sharedModules = [
              dms.homeModules.dank-material-shell
              dms.homeModules.niri
              nixvim.homeModules.nixvim
            ];
          }
        ];
      };
    };
}
