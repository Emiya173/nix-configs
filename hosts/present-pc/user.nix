{ lib, userName, ... }:
{
  environment.etc = {
    "xdg/noctalia/appearance.toml".source = ./noctalia.toml;
    "xdg/noctalia/wallpapers/desktop.jpg".source = ../../assets/noctalia/desktop.jpg;
    "xdg/noctalia/wallpapers/secondary.png".source = ../../assets/noctalia/secondary.png;
  };

  # imv-wayland can submit an invalid buffer size on these fractional-scale outputs.
  hjem.users.${userName}.xdg.mime-apps.default-applications = lib.genAttrs [
    "image/png"
    "image/jpeg"
    "image/gif"
    "image/webp"
  ] (_: lib.mkForce "org.gnome.gThumb.desktop");
}
