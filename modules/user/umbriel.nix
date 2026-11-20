{
  pkgs,
  lib,
  inputs,
  displayConfig,
  desktopFeatures,
  hostPaths,
  userName,
  ...
}:
let
  primaryOutput = displayConfig.primary;
  shell = action: "spawn noctalia msg ${action}";
  controlCenterTab = tab: {
    action = shell "panel-open control-center ${tab}";
    submap = "reset";
    repeat = false;
  };
  mediaKey = action: {
    action = shell action;
    allow_when_locked = true;
  };
  voidmakerToggle = pkgs.writeShellApplication {
    name = "voidmaker-toggle";
    runtimeInputs = [
      pkgs.systemd
      pkgs.util-linux
      pkgs.quickshell
      pkgs.coreutils
    ];
    text = ''
      exec 9>"$XDG_RUNTIME_DIR/voidmaker-toggle.lock"
      flock -n 9 || exit 0
      shell_path=${lib.escapeShellArg "${hostPaths.voidmaker}/apps/shell/shell.qml"}
      if quickshell --path "$shell_path" ipc call voidmaker toggle 2>/dev/null; then
        exit 0
      fi
      state=$(systemctl --user show --property=ActiveState --value voidmaker.target)
      if [ "$state" = deactivating ]; then
        exit 0
      fi
      systemctl --user start voidmaker.target
      # Type=simple 启动完成时，QML 的 IPC 接口可能还未就绪。
      for ((attempt = 0; attempt < 50; attempt++)); do
        if quickshell --path "$shell_path" ipc call voidmaker showUi 2>/dev/null; then
          exit 0
        fi
        sleep 0.2
      done
      echo "VoidMaker 界面尚未就绪" >&2
      exit 1
    '';
  };

  # ExecStopPost 在编码器退出后执行，避免发送 SIGINT 就提前声称文件已保存。
  recordFinished = pkgs.writeShellApplication {
    name = "umbriel-record-finished";
    runtimeInputs = [ pkgs.libnotify ];
    text = ''
      if [ "''${SERVICE_RESULT:-}" = success ] && [ -s "$UMBRIEL_RECORD_OUTPUT" ]; then
        notify-send "录屏" "录制已结束，已保存到 $UMBRIEL_RECORD_OUTPUT" || true
      else
        notify-send --urgency=critical "录屏" "录制未正常完成，请检查 journalctl --user -u umbriel-screen-record.service" || true
      fi
    '';
  };

  # 专用 user service 持有录制进程；同一快捷键只停止自己的录制并等待 SIGINT 收尾。
  recordToggle = pkgs.writeShellApplication {
    name = "umbriel-record-toggle";
    runtimeInputs = [
      pkgs.wf-recorder
      pkgs.slurp
      pkgs.libnotify
      pkgs.systemd
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''
      exec 9>"$XDG_RUNTIME_DIR/umbriel-record-toggle.lock"
      flock -n 9 || exit 0
      unit=umbriel-screen-record.service
      state=$(systemctl --user show --property=ActiveState --value "$unit" 2>/dev/null || true)
      case "$state" in
        active|activating)
          systemctl --user stop "$unit"
          exit 0
          ;;
        deactivating) exit 0 ;;
      esac

      case "''${1:-region}" in
        region)
          geometry=$(slurp) || exit 0
          [ -n "$geometry" ] || exit 0
          args=(-g "$geometry")
          ;;
        audio) args=(--audio -o ${lib.escapeShellArg primaryOutput}) ;;
        *) exit 1 ;;
      esac

      mkdir -p "$HOME/Videos"
      out="$HOME/Videos/$(date +%Y%m%d-%H%M%S-%N).mp4"
      if ! systemd-run --user --unit="$unit" --collect --service-type=exec \
        --property=PartOf=graphical-session.target \
        --property=KillSignal=SIGINT --property=TimeoutStopSec=60s \
        --property=ExecStopPost=${lib.getExe recordFinished} \
        --setenv="UMBRIEL_RECORD_OUTPUT=$out" --setenv="WAYLAND_DISPLAY=$WAYLAND_DISPLAY" \
        ${lib.getExe pkgs.wf-recorder} "''${args[@]}" -f "$out"; then
        notify-send --urgency=critical "录屏" "无法启动录制，请检查 journalctl --user -u $unit" || true
        exit 1
      fi
    '';
  };

  toggleTouchpad = pkgs.writeShellScript "toggle-touchpad" ''
    case "$(umbriel config get input.touchpad.enabled)" in
      true) exec umbriel config set input.touchpad.enabled false ;;
      false) exec umbriel config set input.touchpad.enabled true ;;
    esac
  '';
  releaseOutput = pkgs.writeShellApplication {
    name = "umbriel-release-output";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      windows=$(umbriel windows --json)
      while read -r id; do
        umbriel msg window-focus "$id"
        umbriel msg window-move-to-workspace-silent 1 --output ${lib.escapeShellArg primaryOutput}
      done < <(jq -r --arg output ${lib.escapeShellArg displayConfig.virtual} '.[] | select(.output == $output) | .id' <<< "$windows")
      umbriel msg workspace-switch 1 --output ${lib.escapeShellArg primaryOutput}
    '';
  };
in
{
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
    GLFW_IM_MODULE = "ibus";
  };
  users.users.${userName}.packages = [ pkgs.playerctl ];
  hjem.users.${userName} = {
    imports = [ inputs.umbriel.hjemModules.default ];
    programs.umbriel = {
      enable = true;
      package = null;
      settings = {
        # Noctalia generates the palette after the first shell startup.
        include.optional.files = [ "noctalia.toml" ];
        layer_rule = [
          {
            match.namespace = "^noctalia-(panel|attached-panel|notification|osd)$";
            blur = true;
            blur_ignore_alpha = 0.5;
            blur_popups = true;
          }
        ];
        general = {
          autostart = [ "fcitx5 -d" ];
          show_cheatsheet = false;
          xwayland_native_resolution = true;
          xwayland_primary_output = primaryOutput;
        };
        output = lib.mapAttrs (
          _: output:
          {
            inherit (output) scale;
            focus_at_startup = output.focus-at-startup or false;
            mode = "${toString output.mode.width}x${toString output.mode.height}@${toString output.mode.refresh}";
            position = [
              output.position.x
              output.position.y
            ];
          }
          // lib.optionalAttrs (output ? transform) {
            transform = toString output.transform.rotation;
          }
          // lib.optionalAttrs (output ? variable-refresh-rate) {
            vrr = "fullscreen";
          }
        ) displayConfig.outputs;
        input = {
          keyboard = {
            layout = "us";
            options = "caps:escape";
            repeat_delay = 250;
            repeat_rate = 40;
          };
          touchpad = {
            tap = true;
            natural_scroll = true;
            disable_while_typing = true;
          };
          mouse.accel_profile = "flat";
          cursor = {
            theme = "Bibata-Modern-Classic";
            size = 32;
            follows_focus = true;
          };
          focus.follows_mouse = "sloppy";
        };
        workspaces.back_and_forth = true;
        layout = {
          mode = "scrolling";
          gap = 8;
          scrolling.default_extent_fraction = 0.5;
          extent_presets = [
            0.333
            0.5
            0.667
            1.0
          ];
        };
        appearance.corner_radius = 8;
        # Apply the lone-column width after host-specific startup placement.
        window_rule = lib.mkAfter (
          [
            {
              match.app_id = "^(pavucontrol|blueman-manager|nm-connection-editor|xdg-desktop-portal-gtk|fcitx)$";
              default_floating = true;
            }
            {
              match.app_id = "^(kitty|com[.]mitchellh[.]ghostty|foot)$";
              opacity = 0.75;
              blur = true;
            }
            {
              match.app_id = "^([Cc]ode|neovide|dev[.]zed[.]Zed|herdr-app)$";
              opacity = 0.85;
              blur = true;
            }
            {
              match.app_id = "^dev[.]noctalia[.]Noctalia$";
              opacity = 0.75;
              blur = true;
            }
            {
              match.is_alone = true;
              default_scrolling_extent = 0.667;
            }
          ]
          ++ lib.optional desktopFeatures.voidmaker {
            match.app_id = "^voidmaker$";
            default_floating = true;
            default_position = {
              anchor = "bottom_right";
              x = 32;
              y = 32;
            };
            border_width = 0;
            corner_radius = 0;
          }
        );
        keybinds = {
          "Mod+Return" = "spawn kitty";
          "Mod+T" = "spawn kitty";
          "Ctrl+Alt+T" = "spawn kitty";
          "Mod+E" = "spawn luciole";
          "Mod+W" = "spawn chromium";
          "Mod+Shift+X" = "spawn code";
          "Ctrl+Shift+Alt+Mod+W" = "spawn wps";
          "Ctrl+Mod+V" = "spawn pavucontrol";
          "Ctrl+Shift+Escape" = "spawn kitty -e btop";
          "Mod+M" = "spawn kitty -e btop";
          "Mod+Space" = shell "panel-toggle launcher";
          "Mod+S" = "scratchpad-toggle";
          "Mod+Shift+S" = "window-move-to-scratchpad";
          "Mod+Ctrl+S" = "window-restore-from-scratchpad";
          "XF86Tools" = shell "panel-toggle launcher";
          "Mod+V" = shell "panel-toggle clipboard";
          "Mod+P" = {
            action = "submap panels";
            repeat = false;
          };
          "submap[panels],C" = controlCenterTab "home";
          "submap[panels],N" = controlCenterTab "notifications";
          "submap[panels],M" = controlCenterTab "media";
          "submap[panels],A" = controlCenterTab "audio";
          "submap[panels],S" = controlCenterTab "system";
          "submap[panels],Escape" = "submap reset";
          "Mod+I" = shell "settings-toggle";
          "Mod+Slash" = "cheatsheet-toggle";
          "Mod+Alt+L" = shell "session lock";
          "Mod+Alt+N" = shell "nightlight-toggle";
          "Mod+BackSpace" = shell "panel-toggle session";
          "Mod+X" = shell "panel-toggle session";
          "Mod+Shift+E" = "session-quit";
          "Mod+Shift+Escape" = shell "session lock-and-suspend";
          "Ctrl+Shift+Alt+Mod+Delete" = "spawn systemctl poweroff";
          "Mod+C" = "window-close";
          "Alt+F4" = "window-close";
          "Mod+F" = "window-toggle-fullscreen";
          "Mod+D" = "window-toggle-maximize";
          "Mod+Alt+Space" = "window-toggle-floating";
          "Mod+H" = "window-focus-or-output-left";
          "Mod+L" = "window-focus-or-output-right";
          "Mod+BracketLeft" = "window-focus-or-output-left";
          "Mod+BracketRight" = "window-focus-or-output-right";
          "Mod+J" = "window-focus-down";
          "Mod+K" = "window-focus-up";
          "Mod+Shift+H" = "column-move-left";
          "Mod+Shift+L" = "column-move-right";
          "Mod+Shift+J" = "window-move-down";
          "Mod+Shift+K" = "window-move-up";
          "Mod+Comma" = "window-consume-from-right";
          "Mod+Period" = "window-consume-or-expel-right";
          "Mod+R" = "window-cycle-primary-extent";
          "Mod+Shift+R" = "window-cycle-secondary-extent";
          "Mod+Minus" = "window-modify-primary-extent -0.1";
          "Mod+Equal" = "window-modify-primary-extent 0.1";
          "Mod+Page_Up" = "workspace-previous";
          "Mod+Page_Down" = "workspace-next";
          "Mod+U" = "workspace-next";
          "Mod+Shift+U" = "column-move-to-workspace-next";
          "Mod+Shift+I" = "column-move-to-workspace-previous";
          "Mod+Alt+Page_Up" = "workspace-move-up";
          "Mod+Alt+Page_Down" = "workspace-move-down";
          "Mod+Tab" = "overview-toggle";
          "Alt+Tab" = {
            action = shell "window-switcher hold";
            repeat = false;
          };
          "Alt+Shift+Tab" = {
            action = shell "window-switcher hold reverse";
            repeat = false;
          };
          "Mod+WheelDown" = "window-focus-right";
          "Mod+WheelUp" = "window-focus-left";
          "Mod+Shift+WheelDown" = "column-move-right";
          "Mod+Shift+WheelUp" = "column-move-left";
          "Print" = shell "screenshot-region";
          "Ctrl+Print" = shell "screenshot-fullscreen";
          "Alt+Print" = shell "screenshot-window";
          "Mod+Shift+A" = shell "screenshot-annotate";
          "Mod+Shift+C" = "spawn hyprpicker -a";
          "Mod+Ctrl+R" = "spawn ${lib.getExe recordToggle} region";
          "Mod+Ctrl+Shift+R" = "spawn ${lib.getExe recordToggle} audio";
          "XF86AudioRaiseVolume" = mediaKey "volume-up 3%";
          "XF86AudioLowerVolume" = mediaKey "volume-down 3%";
          "XF86AudioMute" = mediaKey "volume-mute";
          "XF86TouchpadToggle" = "spawn ${toggleTouchpad}";
          "XF86TouchpadOn" = "spawn umbriel config set input.touchpad.enabled true";
          "XF86TouchpadOff" = "spawn umbriel config set input.touchpad.enabled false";
          "XF86AudioMicMute" = mediaKey "mic-mute";
          "XF86MonBrightnessUp" = mediaKey "brightness-up";
          "XF86MonBrightnessDown" = mediaKey "brightness-down";
          "Mod+Shift+M" = shell "volume-mute";
          "Mod+Alt+M" = shell "mic-mute";
          "XF86AudioPlay" = shell "media toggle";
          "XF86AudioPause" = shell "media toggle";
          "XF86AudioNext" = shell "media next";
          "XF86AudioPrev" = shell "media previous";
          "Mod+Shift+P" = shell "media toggle";
          "Mod+Shift+N" = shell "media next";
          "Mod+Shift+B" = shell "media previous";
        }
        // lib.mergeAttrsList (
          lib.imap1
            (index: key: {
              "Mod+${key}" = "workspace-switch ${toString index}";
              "Mod+Shift+${key}" = "column-move-to-workspace ${toString index}";
            })
            [
              "1"
              "2"
              "3"
              "4"
              "5"
              "6"
              "7"
              "8"
              "9"
              "0"
            ]
        )
        // lib.mergeAttrsList (
          lib.mapAttrsToList
            (key: direction: {
              "Mod+Ctrl+${key}" = "output-focus-${direction}";
              "Mod+Ctrl+Shift+${key}" = "column-move-to-output-${direction}";
            })
            {
              H = "left";
              J = "down";
              K = "up";
              L = "right";
            }
        )
        // lib.optionalAttrs desktopFeatures.voidmaker { "Mod+A" = "spawn ${lib.getExe voidmakerToggle}"; }
        // lib.optionalAttrs desktopFeatures.casting {
          "Mod+Alt+P" = "screencast-set-window";
          "Mod+Alt+Shift+P" = "screencast-clear";
          "Mod+Alt+O" = "window-move-to-workspace-silent 1 --output ${displayConfig.virtual}";
          "Mod+Alt+Shift+O" = "spawn ${lib.getExe releaseOutput}";
        };
      };
    };
  };
}
