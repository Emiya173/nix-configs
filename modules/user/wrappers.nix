{
  config,
  pkgs,
  lib,
  inputs,
  userName,
  ...
}:

let
  wrappers = inputs.nix-wrapper-modules.wrappers;
  kittyDmsIncludes = pkgs.writeText "kitty-dms-includes.py" ''
    import os
    from pathlib import Path

    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    for name in ("dank-tabs.conf", "dank-theme.conf"):
        path = config_home / "kitty" / name
        if path.is_file():
            print(f"include {path.absolute()}")
  '';

  # 按设备类型汇总，避免设备顺序变化影响 Swap_Zram / Swap_Disk 的标签。
  swapUsage = kind: ''
    LC_ALL=C ${lib.getExe pkgs.gawk} -v kind=${lib.escapeShellArg kind} '
      function size(kib, units, i) {
        if (kib == 0) return "0 B"
        split("KiB MiB GiB TiB PiB", units, " ")
        for (i = 1; kib >= 1024 && i < 5; i++) kib /= 1024
        return sprintf("%.1f %s", kib, units[i])
      }
      NR > 1 {
        isZram = $1 ~ /^\/dev\/zram[0-9]+$/
        if ((kind == "zram") == isZram) {
          used += $4
          total += $3
        }
      }
      END {
        printf "%s / %s (%.0f%%)\n", size(used), size(total), (total > 0 ? used / total * 100 : 0)
      }
    ' /proc/swaps
  '';

  kitty = wrappers.kitty.wrap {
    inherit pkgs;

    # Kitty dispatches its special entry points before parsing --config.
    # Keep them usable, including the +open command in kitty-open.desktop.
    runShell = [
      ''
        case "''${1-}" in
          +open)
            shift
            exec ${lib.getExe pkgs.kitty} +open --config ${placeholder "out"}/kitty.conf "$@"
            ;;
          +)
            if [ "''${2-}" = open ]; then
              shift 2
              exec ${lib.getExe pkgs.kitty} +open --config ${placeholder "out"}/kitty.conf "$@"
            fi
            exec ${lib.getExe pkgs.kitty} "$@"
            ;;
          +*|icat|list-fonts)
            exec ${lib.getExe pkgs.kitty} "$@"
            ;;
        esac
      ''
    ];

    font = {
      name = builtins.head config.fonts.fontconfig.defaultFonts.monospace;
      size = 11;
    };

    settings = {
      # 禁用文件监视: kitty 每实例的 __watch_conf__ 约占 25MB,
      # Home Manager 替换 store symlink 曾触发 watcher 累积泄漏。
      # DMS 通过 SIGUSR1 重载主题,手动重载 ctrl+shift+f5 仍可用。
      auto_reload_config = -1;
      cursor_shape = "beam";
      cursor_trail = 1;
      window_margin_width = "21.75";
      confirm_os_window_close = 0;
      shell = "fish";
      scrollback_lines = 10000;
      enable_audio_bell = "no";
      copy_on_select = "no";
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
    };

    keybindings = {
      "ctrl+c" = "copy_or_interrupt";
      "page_up" = "scroll_page_up";
      "page_down" = "scroll_page_down";
      "ctrl+plus" = "change_font_size all +1";
      "ctrl+equal" = "change_font_size all +1";
      "ctrl+minus" = "change_font_size all -1";
      "ctrl+0" = "change_font_size all 0";
    };

    # Kitty's globinclude rejects absolute patterns after expanding ~ or $HOME.
    # Resolve optional, mutable DMS files on every startup and theme reload.
    extraConfig = ''
      geninclude ${kittyDmsIncludes}
    '';
  };

  fastfetch = wrappers.fastfetch.wrap {
    inherit pkgs;
    settings = {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
      logo = {
        type = "kitty";
        # Assets are immutable; no per-user logo symlink is needed.
        source = ''$(${pkgs.findutils}/bin/find ${../../assets/fastfetch-logo} -name "*.png" | ${pkgs.coreutils}/bin/shuf -n 1)'';
        # 只固定高度，让不同尺寸的图片按原始比例计算宽度。
        height = 22;
      };
      display = {
        separator = " ";
        key.width = 0;
        percent.type = 9;
        size = {
          binaryPrefix = "iec";
          ndigits = 1;
        };
      };
      modules = [
        {
          type = "custom";
          format = "{#38;5;2}┌──────────────────────────── System ────────────────────────────┐{#}";
        }
        {
          type = "os";
          key = "          OS";
          keyColor = "38;5;1";
          format = "{pretty-name} {arch}";
        }
        {
          type = "kernel";
          key = "          Kernel";
          keyColor = "38;5;1";
          format = "{sysname} {release}";
        }
        {
          type = "de";
          key = "          Desktop";
          keyColor = "38;5;1";
          format = "{pretty-name} {version}";
        }
        {
          type = "wm";
          key = "          WM";
          keyColor = "38;5;1";
          format = "{pretty-name} ({protocol-name})";
        }
        {
          type = "terminal";
          key = "          Terminal";
          keyColor = "38;5;1";
          format = "{pretty-name} {version}";
        }
        {
          type = "terminalfont";
          key = "         󰛖 Font";
          keyColor = "38;5;1";
          format = "{name}";
        }
        {
          type = "shell";
          key = "          Shell";
          keyColor = "38;5;1";
          format = "{pretty-name} {version}";
        }
        {
          type = "packages";
          key = "          Packages";
          keyColor = "38;5;1";
          format = "{nix-all} (nix){?flatpak-all}, {flatpak-all} (flatpak){?}";
        }
        {
          type = "custom";
          format = "{#38;5;2}└────────────────────────────────────────────────────────────────┘{#}";
        }
        {
          type = "custom";
          format = "{#38;5;3}┌─────────────────────────── Hardware ───────────────────────────┐{#}";
        }
        {
          type = "host";
          key = "          Host";
          keyColor = "38;5;2";
          format = "{name}";
        }
        {
          type = "cpu";
          key = "          CPU";
          keyColor = "38;5;2";
          format = "{name} @ {freq-max}";
        }
        {
          type = "gpu";
          key = "         󰢮 GPU";
          keyColor = "38;5;2";
          format = "{name} ({type}, {driver})";
        }
        {
          type = "display";
          key = "         󰍹 Display";
          keyColor = "38;5;2";
          format = "{width}x{height} @ {refresh-rate}Hz";
        }
        {
          type = "memory";
          key = "          Memory";
          keyColor = "38;5;2";
          format = "{used} / {total} ({percentage})";
        }
        {
          type = "command";
          key = "          Swap_Zram";
          keyColor = "38;5;2";
          text = swapUsage "zram";
        }
        {
          type = "command";
          key = "          Swap_Disk";
          keyColor = "38;5;2";
          text = swapUsage "disk";
        }
        {
          type = "disk";
          key = "          Disk";
          keyColor = "38;5;2";
          format = "{size-used} / {size-total} ({size-percentage}) - {filesystem} [{mountpoint}]";
          folders = lib.concatStringsSep ":" (
            [ "/" ] ++ lib.optional (builtins.hasAttr "/mnt" config.fileSystems) "/mnt"
          );
        }
        {
          type = "custom";
          format = "{#38;5;3}└────────────────────────────────────────────────────────────────┘{#}";
        }
        {
          type = "custom";
          format = "{#38;5;1}┌──────────────────────────── Status ────────────────────────────┐{#}";
        }
        {
          type = "datetime";
          key = "          Date";
          keyColor = "38;5;3";
          format = "{day-in-month}.{month-pretty}.{year} {hour-pretty}:{minute-pretty}:{second-pretty}";
        }
        {
          type = "processes";
          key = "          Processes";
          keyColor = "38;5;3";
          format = "{result} running";
        }
        {
          type = "command";
          key = "          Installed";
          keyColor = "38;5;3";
          # 根目录创建时间仅作安装时间的近似值；不支持 birth time 时显示 N/A。
          text = ''
            installed=$(stat -c %W / 2>/dev/null) || installed=0
            if [ "$installed" -gt 0 ]; then
              LC_ALL=C date -d "@$installed" '+%d.%m.%Y %H:%M'
            else
              printf 'N/A\n'
            fi
          '';
        }
        {
          type = "command";
          key = "          OS Age";
          keyColor = "38;5;3";
          text = ''
            installed=$(stat -c %W / 2>/dev/null) || installed=0
            now=$(date +%s)
            if [ "$installed" -gt 0 ] && [ "$installed" -le "$now" ]; then
              printf '%s days since install\n' "$(( (now - installed) / 86400 ))"
            else
              printf 'N/A\n'
            fi
          '';
        }
        {
          type = "uptime";
          key = "          Uptime";
          keyColor = "38;5;3";
          format = "{days}d {hours}h {minutes}m";
        }
        {
          type = "battery";
          key = "          Battery";
          keyColor = "38;5;3";
          format = "{capacity} - {status}";
        }
        {
          type = "custom";
          format = "{#38;5;1}└────────────────────────────────────────────────────────────────┘{#}";
        }
        {
          type = "colors";
          paddingLeft = 2;
          symbol = "circle";
        }
        "break"
      ];
    };
  };

  btop = wrappers.btop.wrap {
    inherit pkgs;
    settings = {
      color_theme = "Default";
      theme_background = true;
      truecolor = true;
      vim_keys = false;
      rounded_corners = true;
      graph_symbol = "braille";
      shown_boxes = "cpu mem net proc";
      update_ms = 1300;
      proc_sorting = "cpu lazy";
      proc_per_core = true;
      proc_mem_bytes = true;
      proc_colors = true;
      proc_gradient = true;
    };
  };
in
{
  options.workstation.kittyPackage = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    description = "Kitty with the workstation configuration and mutable DMS theme includes.";
  };

  config = {
    workstation.kittyPackage = kitty;
    users.users.${userName}.packages = [
      config.workstation.kittyPackage
      fastfetch
      btop
    ];
  };
}
