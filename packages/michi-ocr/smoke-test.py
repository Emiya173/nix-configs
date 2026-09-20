"""Check native dependencies and offline checkpoint loading without a display/GPU."""

import socket
from pathlib import Path


def no_network(*args, **kwargs):
    raise AssertionError("OCR model loading attempted a network connection")


socket.socket.connect = no_network
socket.create_connection = no_network

import gi
import torch
import functorch
from surya.detection.loader import DetectionModelLoader
from surya.foundation.loader import FoundationModelLoader
from surya.settings import settings
import michi_ocr.daemon

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, GtkLayerShell

assert torch.__version__ == "2.9.1+rocm6.4", torch.__version__
assert torch.version.hip, "ROCm support missing"
for checkpoint in (settings.DETECTOR_MODEL_CHECKPOINT, settings.FOUNDATION_MODEL_CHECKPOINT):
    assert checkpoint.startswith("/nix/store/"), checkpoint
    assert (Path(checkpoint) / "model.safetensors").is_file()

DetectionModelLoader().processor()
FoundationModelLoader().processor(device="cpu")
print("OCR imports, GTK typelibs and offline model processors passed")
