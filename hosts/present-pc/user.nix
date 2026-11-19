{ userName, ... }:
{
  environment.etc = {
    "xdg/noctalia/appearance.toml".source = ./noctalia.toml;
    "xdg/noctalia/wallpapers/desktop.jpg".source = ../../assets/noctalia/desktop.jpg;
    "xdg/noctalia/wallpapers/secondary.png".source = ../../assets/noctalia/secondary.png;
  };

  hjem.users.${userName}.programs.umbriel.settings = {
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
  };
}
