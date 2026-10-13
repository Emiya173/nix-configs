{
  primary = "DP-1";
  virtual = "HDMI-A-1";
  outputs = {
    "DP-1" = {
      mode = {
        width = 3840;
        height = 2160;
        refresh = 239.99;
      };
      scale = 1.5;
      position = {
        x = 1067;
        y = 0;
      };
      focus-at-startup = true;
      variable-refresh-rate = "on-demand";
    };
    "DP-2" = {
      mode = {
        width = 2560;
        height = 1600;
        refresh = 160.0;
      };
      scale = 1.5;
      transform.rotation = 90;
      position = {
        x = 0;
        y = 0;
      };
    };
    "HDMI-A-1" = {
      mode = {
        width = 1920;
        height = 1080;
        refresh = 60.0;
      };
      scale = 1.0;
      position = {
        x = 3628;
        y = 0;
      };
    };
  };
}
