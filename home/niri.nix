{ config, pkgs, lib, ... }:

let
  # 应用别名 (对应你 hyprland variables.conf 里的 $terminal/$browser/...)
  terminal       = "kitty";
  fileManager    = "dolphin";
  browser        = "firefox";
  textEditor     = "code";
  officeSoftware = "wps";
  volumeMixer    = "pavucontrol";
  taskManager    = "kitty -e btop";
  launcher       = "fuzzel";
  lockCmd        = "swaylock -f";
  brightUpCmd    = "brightnessctl s 5%+";
  brightDownCmd  = "brightnessctl s 5%-";
  volUpCmd       = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5";
  volDownCmd     = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-";
  muteCmd        = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
  micMuteCmd     = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
in
{
  programs.niri.settings = {
    # ----------------- input -----------------
    input = {
      keyboard.xkb = {
        layout = "us";
      };
      touchpad = {
        tap = true;
        natural-scroll = true;
        dwt = true;
      };
      mouse.accel-profile = "flat";
      focus-follows-mouse.enable = false;
      warp-mouse-to-focus.enable = true;
      workspace-auto-back-and-forth = true;
    };

    # ----------------- 输出 / HiDPI -----------------
    # 多显示器: 安装后用 `niri msg outputs` 查具体名字,然后在这里加 outputs."DP-1" = { ... }
    # 默认让 niri 自己排列即可

    # ----------------- 布局 -----------------
    layout = {
      gaps = 8;
      border = {
        enable = true;
        width = 2;
        active.color = "#88c0d0";
        inactive.color = "#3b4252";
      };
      focus-ring.enable = false;
      preset-column-widths = [
        { proportion = 0.33333; }
        { proportion = 0.5;     }
        { proportion = 0.66667; }
        { proportion = 1.0;     }
      ];
      preset-window-heights = [
        { proportion = 0.33333; }
        { proportion = 0.5;     }
        { proportion = 0.66667; }
      ];
      default-column-width = { proportion = 0.5; };
      center-focused-column = "never";
      always-center-single-column = false;
    };

    # ----------------- 杂项 -----------------
    prefer-no-csd = true;
    hotkey-overlay.skip-at-startup = true;
    screenshot-path = "~/Pictures/Screenshots/Screenshot_%Y-%m-%d_%H-%M-%S.png";

    cursor = {
      theme = "Bibata-Modern-Classic";
      size = 32;
    };

    # ----------------- 环境变量 -----------------
    environment = {
      # fcitx5
      QT_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
      SDL_IM_MODULE = "fcitx";
      GLFW_IM_MODULE = "ibus";
      INPUT_METHOD = "fcitx";

      # 中文环境
      LANG = "zh_CN.UTF-8";
      LANGUAGE = "zh_CN:en_US";

      # Qt
      QT_QPA_PLATFORM = "wayland;xcb";
      QT_QPA_PLATFORMTHEME = "qt6ct";

      # 光标
      XCURSOR_THEME = "Bibata-Modern-Classic";
      XCURSOR_SIZE = "32";

      # Electron / chromium 系
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      NIXOS_OZONE_WL = "1";

      # editor
      EDITOR = "nvim";
      VISUAL = "nvim";

      DISPLAY = ":0";
    };

    # ----------------- 启动项 -----------------
    spawn-at-startup = [
      # XWayland (X11 应用必备)
      { command = [ "xwayland-satellite" ]; }

      # 后台守护
      { command = [ "gnome-keyring-daemon" "--start" "--components=secrets" ]; }
      { command = [ "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1" ]; }

      # 剪贴板历史 (要和 modules 中已装的 cliphist 配合)
      { command = [ "sh" "-c" "wl-paste --type text --watch cliphist store" ]; }
      { command = [ "sh" "-c" "wl-paste --type image --watch cliphist store" ]; }

      # 输入法
      { command = [ "fcitx5" "-d" ]; }

      # 通知守护 (如果 quickshell 还没接管,先用 mako/dunst,否则注释掉)
      # { command = [ "mako" ]; }

      # 壁纸 (修改路径或换 swww)
      { command = [ "sh" "-c" "swaybg -i $HOME/Pictures/wallpaper.jpg -m fill || true" ]; }

      # 待 quickshell 自写 niri 版本完成后启用:
      # { command = [ "qs" "-c" "niri" ]; }
    ];

    # ----------------- 窗口规则 -----------------
    window-rules = [
      # 默认圆角
      {
        geometry-corner-radius =
          let r = 8.0; in { top-left = r; top-right = r; bottom-left = r; bottom-right = r; };
        clip-to-geometry = true;
      }
      # pavucontrol/blueman 之类弹窗浮动居中
      {
        matches = [
          { app-id = "^pavucontrol$"; }
          { app-id = "^blueman-manager$"; }
          { app-id = "^nm-connection-editor$"; }
          { app-id = "^org\\.kde\\.polkit-kde-authentication-agent-1$"; }
          { app-id = "^xdg-desktop-portal-gtk$"; }
        ];
        open-floating = true;
      }
      # 输入法候选窗
      {
        matches = [ { app-id = "^fcitx$"; } ];
        open-floating = true;
        focus-ring.enable = false;
        border.enable = false;
      }
    ];

    # ----------------- 键位 -----------------
    binds = with config.lib.niri.actions; {
      # === 应用启动 ===
      "Mod+Return".action       = spawn terminal;
      "Mod+T".action            = spawn terminal;
      "Ctrl+Alt+T".action       = spawn terminal;
      "Mod+E".action            = spawn fileManager;
      "Mod+W".action            = spawn browser;
      "Mod+X".action            = spawn textEditor;
      "Ctrl+Shift+Alt+Mod+W".action = spawn officeSoftware;
      "Ctrl+Mod+V".action       = spawn volumeMixer;
      "Ctrl+Shift+Escape".action = spawn "sh" "-c" taskManager;

      # 启动器 / 剪贴板 / emoji (quickshell 重写后改 ipc 调 quickshell)
      "Mod+D".action            = spawn launcher;
      "Mod+V".action            = spawn "sh" "-c"
        "cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy";
      "Mod+Period".action       = spawn "sh" "-c"
        "fuzzel-emoji";   # 装好后再实现

      # === 窗口操作 ===
      "Mod+C".action            = close-window;
      "Alt+F4".action           = close-window;
      "Mod+F".action            = fullscreen-window;
      "Mod+Shift+F".action      = maximize-column;
      "Mod+Alt+Space".action    = toggle-window-floating;
      "Mod+Space".action        = switch-focus-between-floating-and-tiling;

      # === 焦点 (列内/列间) — vim-style hjkl ===
      "Mod+H".action            = focus-column-left;
      "Mod+L".action            = focus-column-right;
      "Mod+K".action            = focus-window-up;
      "Mod+J".action            = focus-window-down;
      "Mod+BracketLeft".action  = focus-column-left;
      "Mod+BracketRight".action = focus-column-right;

      # === 移动窗口 ===
      "Mod+Shift+H".action      = move-column-left;
      "Mod+Shift+L".action      = move-column-right;
      "Mod+Shift+K".action      = move-window-up;
      "Mod+Shift+J".action      = move-window-down;

      # 列管理
      "Mod+Comma".action        = consume-window-into-column;
      "Mod+Apostrophe".action   = expel-window-from-column;
      "Mod+R".action            = switch-preset-column-width;
      "Mod+Shift+R".action      = switch-preset-window-height;
      "Mod+Minus".action        = set-column-width "-10%";
      "Mod+Equal".action        = set-column-width "+10%";

      # === Workspace (niri 中纵向,用 U/I 类比 hjkl 的上下) ===
      "Mod+Page_Up".action      = focus-workspace-up;
      "Mod+Page_Down".action    = focus-workspace-down;
      "Mod+U".action            = focus-workspace-down;
      "Mod+I".action            = focus-workspace-up;
      "Mod+Shift+U".action      = move-column-to-workspace-down;
      "Mod+Shift+I".action      = move-column-to-workspace-up;
      "Mod+Tab".action          = focus-workspace-previous;

      "Mod+1".action            = focus-workspace 1;
      "Mod+2".action            = focus-workspace 2;
      "Mod+3".action            = focus-workspace 3;
      "Mod+4".action            = focus-workspace 4;
      "Mod+5".action            = focus-workspace 5;
      "Mod+6".action            = focus-workspace 6;
      "Mod+7".action            = focus-workspace 7;
      "Mod+8".action            = focus-workspace 8;
      "Mod+9".action            = focus-workspace 9;
      "Mod+0".action            = focus-workspace 10;

      "Mod+Shift+1".action      = move-column-to-workspace 1;
      "Mod+Shift+2".action      = move-column-to-workspace 2;
      "Mod+Shift+3".action      = move-column-to-workspace 3;
      "Mod+Shift+4".action      = move-column-to-workspace 4;
      "Mod+Shift+5".action      = move-column-to-workspace 5;
      "Mod+Shift+6".action      = move-column-to-workspace 6;
      "Mod+Shift+7".action      = move-column-to-workspace 7;
      "Mod+Shift+8".action      = move-column-to-workspace 8;
      "Mod+Shift+9".action      = move-column-to-workspace 9;
      "Mod+Shift+0".action      = move-column-to-workspace 10;

      "Mod+Alt+Page_Up".action      = move-workspace-up;
      "Mod+Alt+Page_Down".action    = move-workspace-down;

      # 滚轮切 workspace
      "Mod+WheelScrollDown".action  = focus-workspace-down;
      "Mod+WheelScrollUp".action    = focus-workspace-up;
      "Mod+Shift+WheelScrollDown".action = move-column-to-workspace-down;
      "Mod+Shift+WheelScrollUp".action   = move-column-to-workspace-up;

      # 列水平滚动 (niri 特色)
      "Mod+Ctrl+WheelScrollDown".action = focus-column-right;
      "Mod+Ctrl+WheelScrollUp".action   = focus-column-left;

      # === 截图 ===
      "Print".action            = screenshot;
      "Ctrl+Print".action       = screenshot-screen;
      "Alt+Print".action        = screenshot-window;
      "Mod+Shift+S".action      = screenshot;
      # 区域截图直接走 grim+slurp+satty (更接近 hyprshot 体验)
      "Mod+Shift+A".action      = spawn "sh" "-c"
        "grim -g \"$(slurp)\" - | satty --filename - --copy-command wl-copy";

      # === 取色 ===
      "Mod+Shift+C".action      = spawn "hyprpicker" "-a";

      # === 屏幕录制 (wf-recorder) — 避开 Mod+Shift+R (= switch-preset-window-height) ===
      "Mod+Ctrl+R".action       = spawn "sh" "-c"
        "wf-recorder -g \"$(slurp)\" -f $HOME/Videos/$(date +%Y%m%d-%H%M%S).mp4";
      "Mod+Ctrl+Shift+R".action = spawn "sh" "-c"
        "wf-recorder --audio -f $HOME/Videos/$(date +%Y%m%d-%H%M%S).mp4";

      # === 音量 / 麦克风 ===
      "XF86AudioRaiseVolume".action  = spawn "sh" "-c" volUpCmd;
      "XF86AudioLowerVolume".action  = spawn "sh" "-c" volDownCmd;
      "XF86AudioMute".action         = spawn "sh" "-c" muteCmd;
      "XF86AudioMicMute".action      = spawn "sh" "-c" micMuteCmd;
      "Mod+Shift+M".action           = spawn "sh" "-c" muteCmd;
      "Mod+Alt+M".action             = spawn "sh" "-c" micMuteCmd;

      # === 亮度 ===
      "XF86MonBrightnessUp".action   = spawn "sh" "-c" brightUpCmd;
      "XF86MonBrightnessDown".action = spawn "sh" "-c" brightDownCmd;

      # === 媒体 ===
      "XF86AudioPlay".action  = spawn "playerctl" "play-pause";
      "XF86AudioPause".action = spawn "playerctl" "play-pause";
      "XF86AudioNext".action  = spawn "playerctl" "next";
      "XF86AudioPrev".action  = spawn "playerctl" "previous";
      "Mod+Shift+P".action    = spawn "playerctl" "play-pause";
      "Mod+Shift+N".action    = spawn "playerctl" "next";
      "Mod+Shift+B".action    = spawn "playerctl" "previous";

      # === Session ===
      # Mod+L 已被列焦点占用,锁屏改 Super+Escape
      "Super+Escape".action             = spawn "sh" "-c" lockCmd;
      "Mod+Shift+Escape".action         = spawn "systemctl" "suspend";
      "Ctrl+Alt+Delete".action          = spawn "wlogout" "-p" "layer-shell";
      "Ctrl+Shift+Alt+Super+Delete".action = spawn "systemctl" "poweroff";
      "Mod+Shift+E".action              = quit;

      # 显示 niri 内置 hotkey overlay (cheatsheet 替代品)
      "Mod+Slash".action                = show-hotkey-overlay;

      # === Quickshell IPC 占位 ===
      # 等你写完 niri 版本的 quickshell 后,把下面的 spawn 改成
      #   spawn "qs" "-c" "niri" "ipc" "call" "<service>" "<method>"
      # 例如:
      # "Mod+A".action       = spawn "qs" "-c" "niri" "ipc" "call" "sidebarLeft" "toggle";
      # "Mod+N".action       = spawn "qs" "-c" "niri" "ipc" "call" "sidebarRight" "toggle";
      # "Mod+Backspace".action = spawn "qs" "-c" "niri" "ipc" "call" "session" "toggle";
    };

    # ----------------- 窗口动画 -----------------
    animations = {
      enable = true;
      slowdown = 1.0;
    };
  };

  # niri 配套包 (在 home.packages 里加,system 已经有 swaybg/grim/slurp/satty 等)
  home.packages = with pkgs; [
    swaylock-effects
    swayidle
    wlogout
    brightnessctl
    wf-recorder
    playerctl
    cliphist
    fuzzel
  ];

  # swayidle: 锁屏 + 自动休眠
  services.swayidle = {
    enable = true;
    timeouts = [
      { timeout = 600;  command = "${pkgs.swaylock-effects}/bin/swaylock -f"; }
      { timeout = 1200; command = "systemctl suspend"; }
    ];
    events = [
      { event = "before-sleep"; command = "${pkgs.swaylock-effects}/bin/swaylock -f"; }
      { event = "lock";         command = "${pkgs.swaylock-effects}/bin/swaylock -f"; }
    ];
  };

  # fuzzel 配置 (临时,等 quickshell 接管前用)
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        terminal = "kitty";
        font = "JetBrainsMono Nerd Font:size=12";
        layer = "overlay";
        prompt = "❯ ";
      };
    };
  };
}
