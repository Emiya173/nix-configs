{ pkgs, ... }:

{
  # === Steam ===
  # programs.steam.enable 会自动开 32-bit graphics、wrap 环境变量、装 udev rules
  # (32-bit graphics + alsa.support32Bit 已在 modules/graphics.nix + audio.nix 开过)
  programs.steam = {
    enable = true;
    # 串流到手机/掌机/其他 PC 用 (Steam Link / Remote Play Together)
    remotePlay.openFirewall = true;
    # Proton-GE: 社区分支,兼容性比官方 Proton 强 (尤其是反作弊/DRM 游戏)
    # Lutris 也能调用同一份 proton
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  # Steam Controller / Index / Steam Deck dock 等 Valve 设备的 udev rules
  hardware.steam-hardware.enable = true;

  # gamemode: 游戏启动项写 `gamemoderun %command%` 时自动调 CPU governor/进程优先级,
  # 退出游戏自动还原 (装好后 Steam/Lutris 里按游戏手动加,不全局强制)
  programs.gamemode.enable = true;

  # === Lutris (Wine 前端,跑 epic/gog/盗版以及 native Linux 游戏的启动器) ===
  environment.systemPackages = with pkgs; [
    lutris
    wineWow64Packages.stable # 64-bit wine 直接处理 32-bit Win API (wine 9+ 的新方向)
    winetricks               # 装 dll/字体/dotnet 等到 wine prefix
  ];
}
