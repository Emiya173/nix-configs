{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Rust
    rustup        # 用 rustup 管理 toolchain,而非 nixpkgs 的 rust
    cargo-watch
    cargo-edit

    # Node (npm 已随 nodejs_22 自带)
    nodejs_22
    pnpm
    yarn

    # JDK
    jdk21
    gradle
    kotlin

    # Python
    (python3.withPackages (ps: with ps; [
      pip
      pynvim
      pytesseract
      requests
    ]))
    uv
    poetry

    # 编辑器/IDE
    vscode
    # jetbrains.idea-community  # 按需放开

    # 工具 (direnv + nix-direnv 由下面 programs.direnv 自动装,这里不重复)
    just
    typst
    mdbook
    xmake
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableFishIntegration = true;
  };

  # michi-ocr:仓库自带 HM 模块只用来声明式管 config.toml + 把 michi-ocr-trigger
  # 上 PATH(github 输入,可复现)。service=false ⇒ 不用模块那条 Lens-only 服务,
  # 自启服务在下面自己写,指向本地 devshell 的 Surya 路径。密钥不进 config.toml/store。
  services.michi-ocr = {
    enable = true;
    service = false;
    settings = {
      translate_provider = "deepl";
      # 默认不朗读(不自动 TTS);想读时 overlay 里按 t 重读 / m 开关。这样默认也不会去
      # 连 VoiceVox,下面 socket 激活的引擎平时就一直是停的。
      play_on_ocr = false;
    };
  };

  # 开机(图形会话)自启 michi-ocr 守护进程,带 Surya 离线兜底:
  #  - MICHI_OCR_SURYA=1 让本地 devshell 走 .venv(含 torch 2.9.1+rocm6.4),从 uv.lock 冻结安装;
  #  - layer-shell overlay 需 Wayland,故绑 graphical-session.target 而非系统级 boot;
  #  - 讯飞/DeepL 密钥经 EnvironmentFile 注入(env 覆盖 config.toml),不进 nix store。
  systemd.user.services.michi-ocr = {
    Unit = {
      Description = "michi-ocr daemon (local devshell + Surya)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Environment = "MICHI_OCR_SURYA=1";
      ExecStart = "${pkgs.nix}/bin/nix develop /home/present/dev/michi-ocr --command python -m michi_ocr";
      WorkingDirectory = "/home/present/dev/michi-ocr";
      EnvironmentFile = [
        "/home/present/.config/michi-ocr/deepl.env"
        "/home/present/.config/michi-ocr/xfyun.env"
      ];
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # VoiceVox TTS 引擎:socket 激活,用到才拉起。michi-ocr 默认不 TTS,只有真去朗读、首次
  # 连 127.0.0.1:50021 时,systemd 才起容器;空闲 30 分钟后 proxyd 退出 → 容器自动停。
  # 不开机自启、平时零占用。docker 客户端走 docker 组无需 root,镜像按 digest 锁死=可复现。
  # 容器自身发布在 50121,proxyd 把激活端口 50021 转过去(避免与 socket 抢 50021)。
  systemd.user.sockets.voicevox = {
    Unit.Description = "VoiceVox TTS socket (lazy activation on :50021)";
    Socket.ListenStream = "127.0.0.1:50021";
    Install.WantedBy = [ "sockets.target" ];
  };

  systemd.user.services.voicevox = {
    Unit = {
      Description = "VoiceVox TTS socket-activation proxy";
      Requires = [ "voicevox-engine.service" ];
      After = [ "voicevox-engine.service" ];
    };
    Service.ExecStart =
      "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=1800 127.0.0.1:50121";
  };

  systemd.user.services.voicevox-engine = {
    # proxy 一停就没人需要 engine → 自动停掉容器
    Unit.StopWhenUnneeded = true;
    Service = {
      ExecStartPre = "-/run/current-system/sw/bin/docker rm -f michi-voicevox";
      ExecStart =
        "/run/current-system/sw/bin/docker run --rm --name michi-voicevox"
        + " -p 127.0.0.1:50121:50021"
        + " voicevox/voicevox_engine@sha256:eb8c7f46a7d01217d1ff2b6f018261faedeceded3cc756b4fbbf371791ad6c90";
      ExecStop = "/run/current-system/sw/bin/docker stop michi-voicevox";
      # 容器要先加载模型,给足启动时间
      TimeoutStartSec = 120;
    };
  };

  # nvim 配置由 home/nvim.nix (nixvim) 接管
}
