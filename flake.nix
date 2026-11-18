{
  description = "Personal multi-host NixOS configuration";

  inputs = {
    self.submodules = true;

    # 主包源走 stable。升 release 用 ./scripts/bump-release.sh <新版本>,
    # 会一把改掉这里 + nixvim nixos-* 并更新 lock
    # (flake input url 必须是字面量,版本号没法在 Nix 层单点定义)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Selected unstable binaries come from the pinned store-path index.
    multiverse.url = "github:fzakaria/nixpkgs-multiverse";

    # Keep its own pinned nixpkgs so kernel patches and binary cache stay aligned.
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    nix-wrapper-modules = {
      url = "github:nix-community/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia.url = "github:noctalia-dev/noctalia";
    umbriel = {
      url = "github:noctalia-dev/umbriel";
      inputs.nixpkgs.follows = "noctalia/nixpkgs";
    };
    luciole.url = "github:noctalia-dev/luciole";
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "noctalia/nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      userName = "present";

      mkHost =
        hostName:
        let
          displayConfig = import ./hosts/${hostName}/displays.nix;
          hostPaths = import ./hosts/${hostName}/paths.nix { inherit userName; };
          desktopFeatures = {
            casting = hostName == "present-pc";
            voidmaker = hostName == "present-pc";
            entertainment = hostName == "present-pc";
          };
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            sharedPkgs = pkgs;
            inherit
              inputs
              userName
              hostName
              displayConfig
              hostPaths
              desktopFeatures
              ;
          };
          modules = [
            ./hosts/${hostName}/configuration.nix
            inputs.noctalia.nixosModules.default
            inputs.umbriel.nixosModules.default
            inputs.luciole.nixosModules.default
            inputs.noctalia-greeter.nixosModules.default
            ./modules/user
            inputs.nix-index-database.nixosModules.default
            inputs.hjem.nixosModules.default
          ];
        };

      overlay = import ./overlays/default.nix {
        inherit inputs;
      };

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          overlay
        ];
      };
      nixSources = builtins.filter (path: nixpkgs.lib.hasSuffix ".nix" (toString path)) (
        nixpkgs.lib.filesystem.listFilesRecursive ./.
      );
    in
    {
      packages.${system} = {
        inherit (pkgs) qq;
        inherit (pkgs)
          codex
          baidunetdisk
          chatgpt-desktop
          dingtalk
          dwproton-bin
          fastfetch
          nix-tree
          umu-launcher
          xlog
          ;
      };
      formatter.${system} = pkgs.nixfmt;
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.nixfmt
          pkgs.shellcheck
        ];
      };
      checks.${system} = {
        greeter =
          pkgs.runCommand "check-greeter-startup"
            {
              nativeBuildInputs = with pkgs; [
                dbus
                coreutils
                gnugrep
              ];
              WORKSTATION_GREETER =
                self.nixosConfigurations.arch-pc.config.services.greetd.settings.default_session.command;
              PERSONAL_GREETER =
                self.nixosConfigurations.present-pc.config.services.greetd.settings.default_session.command;
              DBUS_SESSION_CONF = "${pkgs.dbus}/share/dbus-1/session.conf";
              MESA_DIR = pkgs.mesa;
            }
            ''
              bash ${./tests/check-greeter.sh}
              touch $out
            '';
        fcitx5-migration = pkgs.runCommand "check-fcitx5-migration" { } ''
          export PYTHONDONTWRITEBYTECODE=1
          export FCITX5_MIGRATION_MODULE=${./scripts/migrate-fcitx5.py}
          ${pkgs.python3}/bin/python3 ${./tests/test_fcitx5_migration.py}
          touch $out
        '';

        windows-vm = pkgs.runCommand "check-windows-vm" { } ''
          export PYTHONDONTWRITEBYTECODE=1
          export WINDOWS_VM_MODULE=${./scripts/windows-vm.py}
          export QEMU_IMG=${pkgs.qemu_kvm}/bin/qemu-img
          export COPY_PROGRAM=${pkgs.coreutils}/bin/cp
          ${pkgs.python3}/bin/python3 ${./tests/test_windows_vm.py}
          touch $out
        '';

        dae-config = pkgs.runCommand "check-dae-config" { } ''
          export PYTHONDONTWRITEBYTECODE=1
          export DAE_CONFIG_MODULE=${./scripts/prepare-dae-config.py}
          export DAE_BIN=${pkgs.unstable.dae}/bin/dae
          ${pkgs.python3}/bin/python3 ${./tests/test_dae_config.py}
          touch $out
        '';

        formatting = pkgs.runCommand "check-nix-formatting" { } ''
          ${nixpkgs.lib.concatMapStringsSep "\n" (
            path: "${pkgs.nixfmt}/bin/nixfmt --check ${path}"
          ) nixSources}
          touch $out
        '';
        scripts =
          pkgs.runCommand "check-maintenance-scripts"
            {
              nativeBuildInputs = [ pkgs.shellcheck ];
            }
            ''
              shellcheck ${./scripts/check.sh} ${./scripts/bump-release.sh} \
                ${./scripts/stage-workstation-state.sh} ${./scripts/preflight-workstation.sh} \
                ${./tests/check-greeter.sh}
              touch $out
            '';
      };
      nixosConfigurations = {
        # 私人主机：双 DP 显示器。
        present-pc = mkHost "present-pc";
        arch-pc = mkHost "arch-pc";
      };
    };
}
