{ base, fetchzip }:

base.overrideAttrs (
  finalAttrs: _: {
    version = "dwproton-11.0-14";

    src = fetchzip {
      url = "https://github.com/dawn-winery/dwproton-mirror/releases/download/${finalAttrs.version}/${finalAttrs.version}-x86_64.tar.xz";
      hash = "sha256-dXtOdfqIU0wWQ0OXDRbHuFTifGJ7ti+Ij4g+a/RV71Q=";
    };
  }
)
