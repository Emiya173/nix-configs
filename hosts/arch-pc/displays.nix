{
  primary = "HDMI-A-1";
  virtual = null;
  outputs."HDMI-A-1" = {
    mode = {
      width = 2560;
      height = 1440;
      # The monitor advertises its nominal 144 Hz mode as 143.967 Hz.
      refresh = 143.967;
    };
    scale = 1.0;
    position = {
      x = 0;
      y = 0;
    };
    focus-at-startup = true;
  };
}
