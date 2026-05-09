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
      # systemd.enable 已经用 user 服务跑 dms run; enableSpawn 会再往
      # niri spawn-at-startup 注入一份 -> 两份 dms 实例 / 两条 bar
      enableSpawn    = false;
      # enableKeybinds 已经把 DMS 键位塞进 programs.niri.settings.binds,
      # includes.enable 又会通过 raw KDL include 同样的键位 -> 重复,关掉
      includes.enable = false;
    };

    # ---- DMS vs 本文件的分工 ----------------------------------------------
    # DMS 设置面板里"键盘快捷键 / 显示 / 光标主题 / 窗口规则"几项会提示
    # "找到配置文件,未导入" —— 那是 DMS 想接管 ~/.config/niri/config.kdl,
    # 但这个文件由 home-manager 写成 nix-store 只读 symlink,DMS 写不回去。
    # 决策: 这四类全部在本文件 (programs.niri.settings) 声明式管理,
    #       DMS 的相关面板只当只读展示;它的导入提示直接在 UI 里 Dismiss。
    # DMS 仍然负责的部分: bar / spotlight / 通知 / 剪贴板面板 / 电源菜单 /
    #                    动态主题 / 壁纸 / 音量亮度 OSD。
    # 想改键位/输出/光标/窗口规则 -> 改本文件,然后 nh os switch。
    # -----------------------------------------------------------------------
  };

  programs.niri.settings = {
    # ----------------- input -----------------
    input = {
      keyboard = {
        xkb = {
          layout = "us";
          options = "caps:escape";
        };
        # niri 默认 600ms / 25cps,首次重复触发偏慢
        repeat-delay = 250;
        repeat-rate  = 40;
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
    # 主屏 = DP-1 (MSI MAG 272U 4K@240Hz),副屏 DP-2 (2560x1600@160Hz) 270° 竖屏摆左侧
    # 逻辑坐标 = 物理像素 / scale: DP-2 旋转后 1067x1707, DP-1 -> 2560x1440
    outputs."DP-1" = {
      mode = { width = 3840; height = 2160; refresh = 239.99; };
      scale = 1.5;
      position = { x = 1067; y = 0; };   # = DP-2 旋转后逻辑宽度
    };
    outputs."DP-2" = {
      mode = { width = 2560; height = 1600; refresh = 160.0; };
      scale = 1.5;
      # niri 旋转方向和直觉相反,90 才是顶部朝左
      transform.rotation = 90;
      position = { x = 0; y = 0; };
    };

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

    # ----------------- workspaces -----------------
    # named workspace (类比 hyprland special workspace / scratchpad)
    # 钉到主屏 DP-1 (副屏太窄,scratch 内容铺满不好用)
    workspaces."scratch" = {
      open-on-output = "DP-1";
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
      # DMS 剪贴板面板靠 cliphist 持久化,wl-paste --watch 把每次复制写进去
      { command = [ "sh" "-c" "wl-paste --type text  --watch cliphist store &
                                wl-paste --type image --watch cliphist store" ]; }
      # niri 没有 primary monitor 字段,启动焦点按 connector 注册顺序 -> 经常落副屏
      # 等 DMS / 输出就绪后强制把焦点切到 DP-1
      { command = [ "sh" "-c" "sleep 1 && niri msg action focus-monitor DP-1" ]; }
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
      # scratchpad 窗口 (Mod+S 自动开的 kitty --class=scratchpad)
      # 默认 column 宽 100% -> 铺满主屏 (单 window 自动占满 column 高度);
      # 不是 fullscreen,所以仍带边框/bar/可被 Mod+, 收别的窗口进列
      {
        matches = [ { app-id = "^scratchpad$"; } ];
        default-column-width = { proportion = 1.0; };
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

      # 列管理 —— Mod+Comma 默认被 DMS niri 集成绑成设置面板,
      # 我们已经把设置面板搬到 Mod+I,这里 mkForce 覆盖
      "Mod+Comma".action        = lib.mkForce consume-window-into-column;
      "Mod+Period".action       = expel-window-from-column;
      "Mod+R".action            = switch-preset-column-width;
      "Mod+Shift+R".action      = switch-preset-window-height;
      "Mod+Minus".action        = set-column-width "-10%";
      "Mod+Equal".action        = set-column-width "+10%";

      # === Workspace (niri 中纵向,用 U/I 类比 hjkl 的上下) ===
      "Mod+Page_Up".action      = focus-workspace-up;
      "Mod+Page_Down".action    = focus-workspace-down;
      "Mod+U".action            = focus-workspace-down;
      # Mod+I 占用为 DMS 设置面板; workspace-up 改用 Mod+Page_Up / Mod+Tab
      # 用 "settings toggle" 而不是 "control-center toggle" —— DMS 这个版本里
      # IPC handler target 名是 settings (control-center 是内部别名,某些参数解析不对)
      "Mod+I".action            = spawn "dms" "ipc" "settings" "toggle";
      "Mod+Shift+U".action      = move-column-to-workspace-down;
      "Mod+Shift+I".action      = move-column-to-workspace-up;
      # Mod+Tab = niri 自带 overview (所有 workspace + 窗口缩略图)
      # 原 focus-workspace-previous 被覆盖,需要"回上一个 workspace"用 Mod+Page_Up/Down 替代
      "Mod+Tab".action          = toggle-overview;

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

      # niri-flake 没把 move-column-to-workspace 暴露成函数(它在 niri 里有多参数),只能走 attrs
      "Mod+Shift+1".action.move-column-to-workspace = [ 1 ];
      "Mod+Shift+2".action.move-column-to-workspace = [ 2 ];
      "Mod+Shift+3".action.move-column-to-workspace = [ 3 ];
      "Mod+Shift+4".action.move-column-to-workspace = [ 4 ];
      "Mod+Shift+5".action.move-column-to-workspace = [ 5 ];
      "Mod+Shift+6".action.move-column-to-workspace = [ 6 ];
      "Mod+Shift+7".action.move-column-to-workspace = [ 7 ];
      "Mod+Shift+8".action.move-column-to-workspace = [ 8 ];
      "Mod+Shift+9".action.move-column-to-workspace = [ 9 ];
      "Mod+Shift+0".action.move-column-to-workspace = [ 10 ];

      "Mod+Alt+Page_Up".action      = move-workspace-up;
      "Mod+Alt+Page_Down".action    = move-workspace-down;

      # === Scratchpad (named workspace "scratch", 类比 hyprland special workspace) ===
      # Mod+S      : toggle —— 在 scratch 时回上一个 workspace;
      #              否则跳进 scratch,空 scratch 自动开 kitty
      # Mod+Ctrl+S : 把当前 column 扔进 scratch (默认跟随焦点过去)
      "Mod+S".action = spawn "sh" "-c" ''
        current=$(niri msg --json workspaces | jq -r '.[] | select(.is_focused) | .name // empty')
        if [ "$current" = "scratch" ]; then
          niri msg action focus-workspace-previous
        else
          # focus-workspace 会跳到 scratch 当前所在 output (可能在副屏);
          # 用 move-workspace-to-monitor DP-1 强制把它搬到主屏 (focus 跟随)
          niri msg action focus-workspace scratch
          scratch_out=$(niri msg --json workspaces | jq -r '.[] | select(.name=="scratch") | .output')
          if [ "$scratch_out" != "DP-1" ]; then
            niri msg action move-workspace-to-monitor DP-1
          fi
          scratch_id=$(niri msg --json workspaces | jq -r '.[] | select(.name=="scratch") | .id')
          count=$(niri msg --json windows | jq --argjson id "$scratch_id" '[.[] | select(.workspace_id==$id)] | length')
          if [ "$count" = "0" ]; then
            # --class=scratchpad 用来匹配下面的 window-rule (铺满 100% 宽)
            kitty --class scratchpad &
          fi
        fi
      '';
      "Mod+Ctrl+S".action.move-column-to-workspace = [ "scratch" ];

      # 滚轮 = 列左右切焦点 (niri 横向布局,滚轮下 = 下一列 = 右)
      # 列内窗口上下切走 Mod+J/K; workspace 切换走 Mod+U/I/Page_Up/Down
      "Mod+WheelScrollDown".action       = focus-column-right;
      "Mod+WheelScrollUp".action         = focus-column-left;
      # Shift+滚轮 = 移动当前列 (拖着 column 跨 column 走)
      "Mod+Shift+WheelScrollDown".action = move-column-right;
      "Mod+Shift+WheelScrollUp".action   = move-column-left;

      # === 屏幕间跳焦点 / 搬窗口 (hjkl) ===
      "Mod+Ctrl+H".action       = focus-monitor-left;
      "Mod+Ctrl+L".action       = focus-monitor-right;
      "Mod+Ctrl+K".action       = focus-monitor-up;
      "Mod+Ctrl+J".action       = focus-monitor-down;
      # 把当前列搬到另一个屏 (跟当前焦点走)
      "Mod+Ctrl+Shift+H".action = move-column-to-monitor-left;
      "Mod+Ctrl+Shift+L".action = move-column-to-monitor-right;
      "Mod+Ctrl+Shift+K".action = move-column-to-monitor-up;
      "Mod+Ctrl+Shift+J".action = move-column-to-monitor-down;

      # === 截图 === (niri-flake 把截图当 attrs 而非 action 函数)
      "Print".action.screenshot = { };
      "Ctrl+Print".action.screenshot-screen = { };
      "Alt+Print".action.screenshot-window = { };
      "Mod+Shift+S".action.screenshot = { };
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

      # === Session ===
      # 电源菜单 (DMS) —— 用户偏好 Mod+Backspace
      "Mod+BackSpace".action               = spawn "dms" "ipc" "powermenu" "toggle";
      "Mod+Alt+L".action                   = spawn "dms" "ipc" "lock" "lock";
      "Mod+Shift+E".action                 = quit;        # 退出 niri = logout 回 SDDM
      "Mod+Shift+Escape".action            = spawn "systemctl" "suspend";
      "Ctrl+Shift+Alt+Super+Delete".action = spawn "systemctl" "poweroff";

      # === Win 单点 launcher ===
      # keyd (modules/keyd.nix) 把 LeftMeta tap 映射成 KEY_F13,但默认 xkb keymap
      # 把 keycode F13 解释成 XF86Tools keysym (老 IBM 键盘 Tools 键的遗留),
      # 所以这里 bind 的是 XF86Tools 而不是 F13。Win 长按仍是 Super modifier
      "XF86Tools".action = spawn "dms" "ipc" "spotlight" "toggle";

      # 键位面板 —— DMS 的 keybinds target.toggleBinds 只对 hyprland 用户生效;
      # niri 用户走 settings.toggleWith 直接打开设置面板的 keybinds tab
      "Mod+Slash".action                   = spawn "dms" "ipc" "settings" "toggleWith" "keybinds";
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
    cliphist       # DMS 剪贴板后端 (spawn-at-startup 里被 wl-paste 喂数据)
    jq             # Mod+S scratch toggle 脚本读 niri msg --json 用
  ];

  # 自动锁屏 + 休眠 (DMS 提供 dms ipc lock lock 给主动锁屏,
  # 但 idle 触发还是要 swayidle/hypridle)
  services.swayidle = {
    enable = true;
    timeouts = [
      { timeout = 600;  command = "dms ipc lock lock"; }
      { timeout = 1200; command = "systemctl suspend"; }
    ];
    events = {
      before-sleep = "dms ipc lock lock";
      lock         = "dms ipc lock lock";
    };
  };
}
