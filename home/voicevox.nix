{ pkgs, ... }:

let
  image = pkgs.voicevox-image;
  imageRef = image.imageId;
  docker = "${pkgs.docker}/bin/docker";
  loadImage = pkgs.writeShellApplication {
    name = "voicevox-load-image";
    runtimeInputs = [ pkgs.docker ];
    text = ''
      if ! docker image inspect ${imageRef} >/dev/null 2>&1; then
        docker load --input ${image}
      fi
    '';
  };
in
{
  # Keep socket activation; the image archive is now part of the HM closure.
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
    Service.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=1800 127.0.0.1:50121";
  };

  systemd.user.services.voicevox-engine = {
    Unit.StopWhenUnneeded = true;
    Service = {
      ExecStartPre = [
        "${loadImage}/bin/voicevox-load-image"
        "-${docker} rm -f michi-voicevox"
      ];
      ExecStart =
        "${docker} run --rm --pull=never --name michi-voicevox" + " -p 127.0.0.1:50121:50021 ${imageRef}";
      ExecStop = "${docker} stop michi-voicevox";
      # Loading from the local archive on first use can take several minutes.
      TimeoutStartSec = 300;
    };
  };
}
