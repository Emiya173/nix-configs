{ config, pkgs, ... }:

{
  # services.keyd 只装 daemon,不装 CLI; 单独把 keyd 放进 systemPackages 以便
  # `sudo keyd monitor` 调试
  environment.systemPackages = [ pkgs.keyd ];

  # 内核层 tap-hold remap —— 让 Win 单点能触发 launcher,长按仍是 Super modifier
  # Umbriel 将这个 F13 对应的 XF86Tools 映射到 Noctalia 启动器。
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main = {
          # overload(layer, action_on_tap)
          # 长按表现为 leftmeta (= Super, Mod 组合键照旧),单点发 F13
          leftmeta = "overload(meta, f13)";
        };
      };
    };
  };
}
