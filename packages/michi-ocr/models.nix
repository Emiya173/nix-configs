{ fetchurl, linkFarm }:

let
  # Versioned upstream checkpoints used by Surya 0.15.4. Local paths bypass
  # Surya's mutable S3 cache and its first-run model downloader entirely.
  model =
    checkpoint: files:
    linkFarm (builtins.replaceStrings [ "/" ] [ "-" ] checkpoint) (
      builtins.attrValues (
        builtins.mapAttrs (name: sha256: {
          inherit name;
          path = fetchurl {
            url = "https://models.datalab.to/${checkpoint}/${name}";
            inherit sha256;
          };
        }) files
      )
    );
in
{
  detection = model "text_detection/2025_05_07" {
    "config.json" = "0f99d8176e3fc194966659cf6f1c52ab9ca1d573f47ba57aca55036ff5267d69";
    "preprocessor_config.json" = "594344843fcd54db03240194c7677b5c459e78d349e68d4a89d7d91e4fa90587";
    "model.safetensors" = "38c3749eeb5f06fc93ed71eeee5cbd86b1945d08f8f74746bda035d41324bd3e";
  };
  recognition = model "text_recognition/2025_08_12" {
    "config.json" = "408e90c1d7b22a23496b004ebd08e5db6c8eb5b46f1f50fb0217ce0143e9c941";
    "preprocessor_config.json" = "f1e63fddad04cc671e414e5493cddbf1b5fdb503f5d744ee33983209ecf2d0f9";
    "model.safetensors" = "05cb537c6373c52a6299054ffeb8eace094cd71dce72bd3336615e1069b09655";
    "added_tokens.json" = "58b54bbe36fc752f79a24a271ef66a0a0830054b4dfad94bde757d851968060b";
    "chat_template.jinja" = "44d5f08f3f72b837eaad09f13a54c1f9f4eb58d75240334548b7fd52a5437fa5";
    "merges.txt" = "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5";
    "tokenizer_config.json" = "60f6e7bc948cedd377a20f01d022ef664d026fbc93d72e0a9bdac233f8632181";
    "special_tokens_map.json" = "6676f091c8bc4d1b50146427cfde92073402866b87b6e39223227931b70083e9";
    "vocab.json" = "87a257b04b17642a0688c98cd1df89c398bda4fee532d6f88b38a659ecb4ac8d";
  };
}
