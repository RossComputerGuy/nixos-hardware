# DC ROMA II

The DC ROMA II is a RISC-V laptop inside of a Framework chassis (FML13V03), powered by the ESWIN EIC7700 SoC with a PowerVR Rogue GPU.

## Features

- Display: **working** (HDMI internal panel, requires backlight-on service)
  - Wayland: **working** (Hyprland tested)
  - X11: **untested**
- GPU driver: **working** (IMG Volcanic / PowerVR — firmware required, see below)
- WiFi: **working** (Intel AX200 via iwlwifi — needs correct date and regulatory domain)
- Bluetooth: **working** (Intel AX200 via btusb)
- Sound: **untested**
- Fingerprint: **untested**
- Battery: **working** (via ChromeOS EC)
- Keyboard: **working** (DeepComputing USB keyboard + ChromeOS EC)

## Installing

This module is designed to install NixOS using **U-Boot with extlinux**
The module configures `generic-extlinux-compatible` as the bootloader.

### Important Notes

**Kernel:** Uses the `fml13v03-6.6.92` branch from DC-DeepComputing, which includes critical display driver fixes over 6.6.18.

**Display:** The backlight defaults to powered-off (`bl_power=4`). This module includes a systemd service to turn it on at boot. If you see no display output, verify `/sys/class/backlight/backlight/bl_power` is `0`.

**Firmware:** You must provide PowerVR GPU and ESWIN SoC firmware separately. Extract from a working Debian/Ubuntu installation:
- `/lib/firmware/rgx.fw.30.3.408.101` — PowerVR GPU firmware
- `/lib/firmware/rgx.sh.30.3.408.101` — PowerVR shader binary
- `/lib/firmware/powervr/rogue_33.15.11.3_v1.fw` — PowerVR Rogue firmware
- `/lib/firmware/eic7x/` — ESWIN SoC firmware (WiFi, ISP, LPCPU)

Add these to `hardware.firmware` in your configuration.

**Boot parameters:** The module sets kernel parameters including `clk_ignore_unused` (prevents display clocks from being gated) and `firmware_class.path=/lib/firmware/eic7x/` (ESWIN firmware path). These are required for display and hardware functionality.

**extlinux.conf:** When manually setting up boot, use `fdt /dtbs/eswin/eic7702-deepcomputing-fml13v03.dtb` (not `fdtdir`) to avoid U-Boot creating a double path.
