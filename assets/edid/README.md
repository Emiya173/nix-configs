# Workstation display EDIDs

## DELL SE2726D (current)

`dell-se2726d.bin` was read from the connected workstation monitor at
`/sys/class/drm/card1-HDMI-A-1/edid` on 2026-10-31. It includes 2560×1440 at
59.950550, 119.997589, and 143.966693 Hz. Niri uses the last mode, rounded to
143.967 Hz (nominally 144 Hz), both with the physical monitor and when headless.

The 256-byte EDID retains its timings and HDMI extension. Numeric and textual
serial numbers are cleared, and the base-block checksum is recomputed.

SHA-256: `f1270c4056199e8967cddc3c66c7aaf78723b9fd2795c309b8f3cf08d7770f38`.

## Philips 275E1 (previous)

`phl-275e1.bin` is retained for the previous monitor. It includes 2560×1440 at
59.950550 and 74.968101 Hz, matching the earlier workstation audit.

Source: [Linux Hardware Project, Philips PHLC20C / PHL 275E1](https://github.com/linuxhw/EDID/blob/9c0c1bffc9c0f1cb2044115149a5ecb1652803f8/Digital/Philips/PHLC20C/478B1F541DCC),
licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

The upstream text repeats the same 256-byte EDID twice. This file keeps one copy,
clears the numeric serial number, and recomputes the base-block checksum. Display
timings and the HDMI extension are unchanged.

SHA-256: `c6d4a4ec2356013c8a1342f5229dfef5308409dde078be7eba22fab5d9e669bf`.
