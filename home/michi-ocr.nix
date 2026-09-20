{ config, pkgs, ... }:

{
  # Trigger and daemon come from the same locked source, including Surya/ROCm.
  # Credentials remain runtime files and are never copied into the store.
  services.michi-ocr = {
    enable = true;
    package = pkgs.michi-ocr;
    backend = "package";
    service = true;
    deeplApiKeyFile = "${config.xdg.configHome}/michi-ocr/deepl.env";
    secretsFile = "${config.xdg.configHome}/michi-ocr/xfyun.env";
    settings = {
      translate_provider = "deepl";
      play_on_ocr = false;
    };
  };
}
