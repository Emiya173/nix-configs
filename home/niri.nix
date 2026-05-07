{ config, pkgs, lib, ... }:

let
  # 应用别名 (对应你 hyprland variables.conf 里的 $terminal/$browser/...)
  terminal       = "kitty";
  fileManager    = "dolphin";
  browser        = "chromium";
  textEditor     = "code";
  officeSoftware = "wps";
  volumeMixer    = "pavucontrol";
  taskManager    = "kitty -e btop";
  # Spotlight (Mod+Space)、剪贴板 (Mod+V)、亮度/音量 等由 DankMaterialShell 接管
  # 这里只保留它没覆盖到的命令
in
{
  # =====================================================
  # DankMaterialShell (DMS) — quickshell-based desktop shell
  # 提供: bar / spotlight / 通知 / 剪贴板 / 设置 / 电源菜单 / 动态主题
  # =====================================================
  programs.dank-material-shell = {
    enable = true;

    # 自动开机启动 dms run (用户级 systemd 服务)
    systemd.enable = true;

    # 各功能开关 (默认全开)
    enableSystemMonitoring  = true;
    enableVPN               = true;
    enableDynamicTheming    = true;
    enableAudioWavelength   = true;
    enableCalendarEvents    = true;
    enableClipboardPaste    = true;

    # niri 集成: 让 DMS 自动注入它的键位 + spawn,不要重复手动写
    niri = {
      enableKeybinds = true;
      enableSpawn    = true;
    };
  };

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
      focus-follows-mouse.enable = true;     # 与 hyprland 默认 (follow_mouse=1) 一致
      warp-mouse-to-focus.enable = true;     # 键盘切焦点时鼠标跟着跳,与上一项互补
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
    # DMS 自带 dms run (剪贴板/通知/壁纸/动态主题/spotlight 都归它)
    # 这里只放 DMS 不管的: xwayland、keyring、polkit、输入法
    spawn-at-startup = [
      { command = [ "xwayland-satellite" ]; }
      { command = [ "gnome-keyring-daemon" "--start" "--components=secrets" ]; }
      { command = [ "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1" ]; }
      { command = [ "fcitx5" "-d" ]; }
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
      # === 应用启动 (DMS 用 Mod+Space 做 spotlight,这里留快捷键给常用程序) ===
      "Mod+Return".action       = spawn terminal;
      "Mod+T".action            = spawn terminal;
      "Ctrl+Alt+T".action       = spawn terminal;
      "Mod+E".action            = spawn fileManager;
      "Mod+W".action            = spawn browser;
      "Mod+Shift+X".action      = spawn textEditor;          # vscode (Mod+X 给 DMS 电源菜单)
      "Ctrl+Shift+Alt+Mod+W".action = spawn officeSoftware;
      "Ctrl+Mod+V".action       = spawn volumeMixer;
      "Ctrl+Shift+Escape".action = spawn "sh" "-c" taskManager;

      # === 窗口操作 ===
      "Mod+C".action            = close-window;
      "Alt+F4".action           = close-window;
      "Mod+F".action            = fullscreen-window;
      "Mod+D".action            = maximize-column;           # 对齐 hyprland (Super+D = maximize)
      "Mod+Alt+Space".action    = toggle-window-floating;
      # Mod+Space 让给 DMS spotlight

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

      # 列管理 (Mod+Comma 让给 DMS 设置面板)
      "Mod+G".action            = consume-window-into-column;
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

      # === 音量 / 亮度 ===
      # XF86Audio* / XF86MonBrightness* 由 DMS 接管 (走 dms ipc audio/brightness ...)
      # Mod+Shift+M 留给手动静音作为快捷键备份
      "Mod+Shift+M".action           = spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";
      "Mod+Alt+M".action             = spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle";

      # === 媒体 ===
      "XF86AudioPlay".action  = spawn "playerctl" "play-pause";
      "XF86AudioPause".action = spawn "playerctl" "play-pause";
      "XF86AudioNext".action  = spawn "playerctl" "next";
      "XF86AudioPrev".action  = spawn "playerctl" "previous";
      "Mod+Shift+P".action    = spawn "playerctl" "play-pause";
      "Mod+Shift+N".action    = spawn "playerctl" "next";
      "Mod+Shift+B".action    = spawn "playerctl" "previous";

      # === Session (DMS 提供 Mod+X 电源菜单 + Super+Alt+L 锁屏) ===
      # 这里保留兜底
      "Mod+Shift+Escape".action            = spawn "systemctl" "suspend";
      "Ctrl+Shift+Alt+Super+Delete".action = spawn "systemctl" "poweroff";
      "Mod+Shift+E".action                 = quit;

      # 显示 niri 内置 hotkey overlay
      "Mod+Slash".action                   = show-hotkey-overlay;
    };

    # ----------------- 窗口动画 -----------------
    animations = {
      enable = true;
      slowdown = 1.0;
    };
  };

  # niri 配套包 — 启动器/剪贴板/通知/电源菜单/壁纸都由 DMS 提供
  # 这里只放 DMS 没覆盖的功能
  home.packages = with pkgs; [
    wf-recorder    # 屏幕录制 (Mod+Ctrl+R 键位用)
    playerctl      # 媒体键 (Mod+Shift+N/B/P 键位用)
  ];

  # 自动锁屏 + 休眠 (DMS 提供 dms ipc lock lock 给主动锁屏,
  # 但 idle 触发还是要 swayidle/hypridle)
  services.swayidle = {
    enable = true;
    timeouts = [
      { timeout = 600;  command = "dms ipc lock lock"; }
      { timeout = 1200; command = "systemctl suspend"; }
    ];
    events = [
      { event = "before-sleep"; command = "dms ipc lock lock"; }
      { event = "lock";         command = "dms ipc lock lock"; }
    ];
  };
}
