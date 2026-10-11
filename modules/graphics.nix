{ config, pkgs, ... }:

{
  # LACT: AMD GPU 风扇曲线/降压/功耗墙 (daemon + `lact gui`)
  # overdrive 解锁 pp table 调节 (加 amdgpu.ppfeaturemask 内核参数)
  services.lact.enable = true;
  hardware.amdgpu.overdrive.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      vulkan-loader
      vulkan-validation-layers
      libva
      # Mesa 已移除 VDPAU；旧应用按需设置 VDPAU_DRIVER=va_gl，使用 VA-API 桥。
      libvdpau-va-gl
      rocmPackages.clr
      rocmPackages.clr.icd
    ];
    extraPackages32 = [
      pkgs.pkgsi686Linux.vulkan-loader # 32-bit vulkan 不在 driversi686Linux 命名空间
    ];
  };

  environment.systemPackages = with pkgs; [
    vulkan-tools
    mesa-demos # 包含 glxinfo (顶层 glxinfo 已合并进 mesa-demos)
    libva-utils
    vdpauinfo
    clinfo
    nvtopPackages.amd
  ];

  environment.variables = {
    LIBVA_DRIVER_NAME = "radeonsi";
  };
}
