# Virtual Boy core with 3D shutter-glasses output

The Virtual Boy core from [misteraddons/VirtualBoy_MiSTer](https://github.com/misteraddons/VirtualBoy_MiSTer) (upstream commit `eb93244`)
plus an **Eye Sequential (3D shutter glasses)** mode, so Virtual Boy games can be played in real stereo 3D on a **CRT** with
Bluetooth 3D shutter glasses driven by the ESP32 emitter in `../emitter`. No modification of the glasses, no USER port.

Tested with Samsung SSG-4100GB glasses on a 15 kHz CRT.

## How it works

The Virtual Boy has two displays, one per eye, drawn together. In Eye Sequential mode the core's public (CRT) raster shows
**one eye per video frame**, alternating left and right, and the core tells the emitter which eye each frame carries and when it starts.

* The raster is shortened to **256 lines** (the 60 Hz compatibility raster minus 6 lines): one frame is 16.27 ms (61.5 Hz), a
  left+right pair is **32.54 ms**, inside the ~32.7 ms limit of the glasses' frame period counter (see `../docs/PROTOCOL_NOTES.md`).
  The console itself runs at its normal speed; only the CRT raster changes, so the game and audio are not sped up.
* `rtl/vb_eyesync.sv` writes one event per frame into the DDR3 ring at physical `0x3DFFF000` (same layout as the SMS core, see
  the top-level README; flags bit6 = the 40 MHz Virtual Boy clock). The emitter locks to those exact frame starts.
* `rtl/VIP/vip_host_display.sv` / `rtl/vb_video_output.sv` / `rtl/VIP/vip_core.sv` carry the shutter raster
  through the video path; `VirtualBoy.sv` adds the OSD options and the eye-parity logic.

## Use

1. Install the release zip `VirtualBoy3D_install_*.zip` on the MiSTer SD card (adds `_Console/VirtualBoy3D_*.rbf` and the same
   `Scripts/` emitter files as the other cores) and flash/plug in the ESP32 as described in the top-level README.
2. Load the core and a ROM. OSD > **Audio & Video**:
   * **Eye Sequential (3D shutter glasses): On**
   * **Shutter Eye Order**: Swapped if the depth looks inside-out.
3. Run **3D_Glasses_Start** from the Scripts menu and short-press the glasses next to the ESP32.

The picture is red/black as on the real console. The Virtual Boy's own 3D separation can be tuned in the core's *Stereo Scale* menu.
There is no *Sync adjust* OSD option in this build; the same fine adjustment is available on the MiSTer with
`echo adj=50 > /tmp/3d_ctl` (microseconds, positive or negative, applied live).

## Building

`quartus_sh --flow compile VirtualBoy` with Quartus Prime Lite 17.0 (copy the folder to a short path without spaces first).
`vb_3d_glasses.patch` is the change against the upstream commit; `sim/tb_vb_eyesync.sv` is a ModelSim testbench for the event writer.
The upstream README is kept as `README_upstream.md`; the licence is the upstream one (GPL-2.0-or-later).
