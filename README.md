# MiSTer 3D shutter glasses

Drive **Bluetooth 3D shutter glasses** from a MiSTer so that 3-D games work on a **240p CRT**, with no modification of
the glasses and without using the MiSTer's USER port:

* **Sega Master System** 3-D games (Space Harrier 3-D, Missile Defense 3-D, Maze Hunter 3-D, Blade Eagle 3-D, Zaxxon 3-D,
  Poseidon Wars 3-D, OutRun 3-D, Line of Fire) - core in `SMS/`.
* **Nintendo Virtual Boy** (all games are stereo) - core in `VirtualBoy/`.

```
SMS core (FPGA)          MiSTer ARM / Linux                               USB dongle (ESP32)
 Z80 write to $FFF8 -->  DDR3 event ring  -->  emitter/mister_bt3d.py  --USB serial (HCI)-->  Bluetooth 3D
 (which eye is open)     (read via /dev/mem)   phase lock + shutter beacon                     beacon --> glasses
```

Status: **working** with a pair of Samsung SSG-4100GB glasses on an NTSC Master System (Space Harrier 3-D, Zaxxon 3-D) and on the
Virtual Boy core. Nothing else has been tested.

## What you need

* A MiSTer with the SMS core replaced by `SMS3D_*.rbf`, and/or the Virtual Boy core by `VirtualBoy3D_*.rbf`
  (drop-in builds of the official cores plus the changes below).
* An **ESP32** dev board with a USB-serial chip (CP210x or similar), flashed once with the HCI bridge firmware.
  Its Bluetooth controller implements the Bluetooth 4.1 connectionless-broadcast and synchronization-train commands
  that a 3D display needs. The MiSTer's own Realtek Bluetooth adapter does **not** work (see `docs/PROTOCOL_NOTES.md`).
* **Bluetooth 3D glasses of the 2011-12 "Full HD 3D Glasses Initiative" generation** (Samsung SSG-4100GB tested).
  They follow the "Reference Protocol" in Appendix 12 of the public Bluetooth SIG *3D Synchronization Profile*.
* A **CRT**. Passive (polarised) glasses cannot work on a CRT, which emits unpolarised light.

## Install

Everything is in the release as `SMS3D_install_YYYYMMDD.zip`: unzip it onto the root of the MiSTer's SD card
(it contains `_Console/SMS3D_*.rbf`, `Scripts/3D_Glasses_Start.sh`, `Scripts/3D_Glasses_Stop.sh` and
`Scripts/3d_glasses/*.py`).

1. **Flash the ESP32** (once): `esptool.py --chip esp32 write_flash 0x0 esp32_hci_bridge_merged.bin`
   (from the release), or build `esp32/hci_bridge` with PlatformIO. Plug it into a MiSTer USB port; it shows up as
   `/dev/ttyUSB0` (the CP210x driver is in the MiSTer kernel).
2. Load the **SMS3D** core and set, in the OSD under **3D Glasses**:
   * **USB sync output: On**
   * **Glasses sync clock +2.2%: On** (NTSC only, see below)
   * **Eye order**: Swapped if the picture looks inside-out.
   * **Sync adjust (ms)**: shifts both lens windows in 0.05 ms steps (0 to +1.00 / -1.00 to -0.05 ms). If a picture is "on the
     edge" of being in sync (a little ghosting of one eye into the other, worse at deep 3D), nudge it either way until the
     ghosting is lowest. The emitter picks the change up within a fraction of a second; nothing needs restarting.
3. Start a 3D game, then run **3D_Glasses_Start** from the MiSTer *Scripts* menu (log: `/tmp/3d_glasses.log`).
   *3D_Glasses_Stop* stops it and resets the ESP32.
4. Synchronise the glasses: the first time, hold their pairing button next to the ESP32 until the LED flashes;
   afterwards a short press re-synchronises them. The synchronization train runs for an hour per start of the emitter.

## Why the clock option exists (and what it costs)

The Master System shows one eye per video frame, so a left+right pair lasts 33.38 ms (29.97 Hz). The glasses
announce support for 48-120 Hz frame rates, and in practice they stop working above a frame period of **32.7 ms**:
the period counter is 15 bits wide, so longer periods wrap around and the later lens stays black. The glasses also free-run
on the announced period after they lock and ignore later phase corrections, so a period that is merely announced
shorter than the game's real one makes the picture roll between normal and inverted depth.

The only way to hold a lock is therefore to make the game's real pair period fit: with **Glasses sync clock +2.2%**
the core's PLL runs at 54.8868 MHz instead of 53.693 MHz, which makes the pair 32.65 ms. Costs: the game and its music
run 2.2% fast (a slight pitch rise), the CRT sees about 61 Hz, and **PAL is not supported** (it would need +22%).
The option is off by default and only takes effect with USB sync output on.

## Repository layout

One folder per emulator core (`SMS/`, `VirtualBoy/`), shared tools in `emitter/` (runs on the MiSTer) and `esp32/` (dongle firmware), notes in
`docs/`. Core binaries (`.rbf`) are not kept in the repository, only in the releases.

## What was changed in the SMS core

| File | Change |
|---|---|
| `SMS/rtl/system.vhd` | Snoops Z80 memory writes to `$FFF8-$FFFB` (the real adapter ignores A1:A0): bit 0 = `1` left lens open, `0` right lens open, plus a write pulse. |
| `SMS/rtl/glasses3d.sv` (new) | Tracks whether a 3-D game is running and publishes write events and frame-start events to a DDR3 ring, plus the settings word (sync adjust). |
| `SMS/SMS.sv` | OSD page **3D Glasses** (USB sync output, +2.2% clock, eye order, sync adjust); shares the DDR3 port with savestates and the screen rotator; the +2.2% PLL mode. |
| `SMS/files.qip` | Adds `rtl/glasses3d.sv`. |

`SMS/sms_3d_glasses.patch` is the change against upstream [MiSTer-devel/SMS_MiSTer](https://github.com/MiSTer-devel/SMS_MiSTer)
commit `8443a0d`. The full buildable source is in `SMS/` (Quartus Prime Lite 17.0: `quartus_sh --flow compile SMS`).

### Event ring (DDR3 physical address 0x3DFFF000)

64 entries of 64 bytes (entry = sequence number mod 64); only the first 64-bit word of an entry is used.
Little endian, `struct.unpack('<IBBH', word)` gives `(ts, magic, flags, seq)`:

| Bits | Field |
|---|---|
| 63:48 | sequence number, +1 per event |
| 47:40 | flags: bit0 left lens open, bit1 3-D game active, bit2 PAL, bit3 enabled, bit4 frame-start event (0 = write event), bit5 +2.2% clock, bit6 40 MHz clock (the Virtual Boy core) |
| 39:32 | magic 0x5D |
| 31:0 | core clock cycle counter at the event (wraps about every 80 s) |

A settings word sits in the 64-byte block just below the ring (physical `0x3DFFEFC0`): byte 7 = `0x5E`, byte 6 = version 1,
byte 5 = Sync adjust index (0..20 = 0..+1.00 ms, 21..40 = -1.00..-0.05 ms). The core rewrites it when the option changes and every
few seconds, and the emitter shifts both lens windows by it.

Events: every game write to `$FFF8-$FFFB`, and **every frame start** while a 3-D game runs (exact video timing, which the
emitter locks to). The ARM reads the FPGA's 64-bit write as two 32-bit loads, so readers re-read an entry until two reads agree.

## How the emitter works

`emitter/mister_bt3d.py` runs on the MiSTer. It reads the ring, estimates the game's frame period against the Bluetooth
controller's clock (including the ratio between the FPGA's and the ESP32's crystals, to a few ppm), and acts as a
Bluetooth 3D display: it answers the glasses' inquiry, runs the synchronization train, and broadcasts the shutter-timing
beacon. Details of what the glasses accept and ignore are in `docs/PROTOCOL_NOTES.md`.

* `emitter/bt3dd.py` - display-side protocol library and test tool (`check` / `assoc` / `beacon`, many variations).
* `emitter/bt3dg.py` - glasses simulator: receives and decodes another adapter's train and beacon.
* `emitter/mister_glasses_daemon.py` and `emitter/rp2040/main.py` - an untested infrared path for Sony glasses.
* `SMS/sim/` - ModelSim testbench for `glasses3d`; `emitter/tests/` - a simulation of the timing estimators.

While the emitter runs it re-reads `/tmp/3d_ctl` (key=value pairs such as `lead=1500 tail=2700 shift=0 swap=0`) so the
shutter windows can be tuned live: `lead`/`tail` are how long before its picture each lens opens and before the next
picture it starts closing, `shift` moves both windows.

## Licence and credits

GPL-2.0-or-later, like the core it builds on. The SMS core is Sorgelig's MiSTer port and contributors' work
(see `SMS/README_upstream.md`). The Bluetooth 3D Synchronization Profile is a public Bluetooth SIG specification.
