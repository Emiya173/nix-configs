{ config, pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      mesa
      vulkan-loader
      vulkan-validation-layers
      libva
      libva-utils
      vaapiVdpau
      libvdpau-va-gl
      rocmPackages.clr
      rocmPackages.clr.icd
    ];
    extraPackages32 = with pkgs.driversi686Linux; [
      mesa
      vulkan-loader
    ];
  };

  environment.systemPackages = with pkgs; [
    vulkan-tools
    glxinfo
    libva-utils
    vdpauinfo
    clinfo
    nvtopPackages.amd
  ];

  environment.variables = {
    LIBVA_DRIVER_NAME = "radeonsi";
    VDPAU_DRIVER = "radeonsi";
  };
}
