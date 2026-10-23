# Notes on driving Bluetooth 3D shutter glasses

What was measured while building this, in case it helps with other cores or other glasses. Everything below was
observed on one pair of **Samsung SSG-4100GB** glasses with an **ESP32** (ESP32-D0WD-V3) as the 3D display. "Observed"
means the glasses were watched by a person; where a cause is a guess it says so.

## The protocol

The glasses follow the "Reference Protocol" in Appendix 12 of the Bluetooth SIG *3D Synchronization Profile* (public):

1. The glasses **inquire**; the display answers with class of device `0x00043C` and a manufacturer-specific EIR record
   (Broadcom, 3D information) marking it as a 3D display.
2. The glasses **page** the display once and abort; the display answers by starting the **synchronization train**
   (`Start_Synchronization_Train`, three DM3 packets on 2402/2426/2480 MHz every 80 ms).
3. The glasses receive the train (it carries the display's clock, AFH map, next beacon instant and beacon interval), then
   follow a **connectionless slave broadcast** (LT_ADDR 1, DM1, one 17-byte payload every 80 ms):

   | Bytes | Field |
   |---|---|
   | 0-3 | Bluetooth clock (28 bits, 312.5 us ticks) at the rising edge of the frame sync |
   | 4-5 | clock phase in us (0-312) |
   | 6-7, 8-9 | left lens open / close offset (us from the sync instant); `0xFFFF` open offset = 2D mode, both lenses open |
   | 10-11, 12-13 | right lens open / close offset |
   | 14-15 | frame sync period in us |
   | 16 | period fraction in 1/256 us |

HCI commands used: `Write_Class_of_Device`, `Write_Extended_Inquiry_Response`, `Write_Scan_Enable`,
`Write_Sync_Train_Parameters`, `Set_Reserved_LT_ADDR`, `Set_Connectionless_Slave_Broadcast`,
`Set_Connectionless_Slave_Broadcast_Data`, `Start_Synchronization_Train`, `Read_Clock`.

## What the glasses accept and what they do not

* **Frame period.** Left+right periods of 31.0 and 32.7 ms shutter both lenses; 33.0, 33.4 and 34.0 ms leave the lens whose
  window opens later black. 48 Hz (20.8 ms) works. This fits a 15-bit microsecond period counter (limit 32 768 us); that
  explanation is a guess, the cut-off is observed. A Master System pair is 33.38 ms, hence the +2.2% core clock.
* **Free-running.** After locking, the glasses keep running on the announced period. Changing the sync instant in later
  beacons (leading it, lagging it, centring the drift, 20 ms beacons, perfectly regular beacons) did not make them follow
  a source whose real period differed from the announced one: the picture rolled between normal and inverted depth at the
  same rate in every case. Matching the periods (to a few ppm) gave a steady picture.
* **Clock stamping.** Sync instants stamped in the true Bluetooth clock (3200 ticks/s) that keep pace with real time put the
  right lens into a strange state (mostly black with streaks, not damage; recovers when the beacon changes). The ESP32's raw
  `Read_Clock` units (1600/s) did not. What cured it was announcing a sync instant that **lags real time by whole announced
  periods**, growing at half real-time speed (`slag=0.5` in the emitter); window positions are unchanged because the glasses
  extrapolate by whole periods. Why this works is not understood.
* **Beacon geometry.** Keep all four offsets inside the announced period; windows that run past it behave like a wrapped period.
* **Beacon interval.** Announcing 20 ms instead of 80 ms in the train changed nothing visible.
* **Short press** re-synchronises previously paired glasses without an inquiry; the train must be running. The glasses give
  up searching after about 10-12 s.

## ESP32 controller quirks

* `Read_Clock` returns 625 us units (1600/s), not 312.5 us ticks.
* The controller never reports inquiry or page events (0x56 / 0x54) to the host, so a host cannot see the glasses
  searching.
* Disabling the broadcast while it runs makes the controller assert (`ld_csb_tx.c`); the emitter resets the ESP32 instead.
* The spec's maximum synchronization train timeout (`0x07BFA000` slots) makes the controller stop answering
  `Start_Synchronization_Train`; one hour (5 760 000 slots) works. The train must be running whenever the glasses are
  asked to synchronise, so a short timeout with an unchecked restart makes later synchronisation attempts fail silently.
* Under USB bus errors the CP210x can drop off and re-enumerate; the emitter reopens it and configures the controller again.

## Other controllers

The MiSTer's Realtek RTL8761-class USB adapter (HCI 5.1) accepts every command and the glasses page it, but its connectionless
broadcast goes out on schedule with a **zero-length payload**: the shutter beacon never leaves the adapter (other command
orders, fragment flags, one-shot or repeated data, payload sizes 5-28 bytes made no difference). Its train announces an empty
AFH map unless `--afh-all` is used. The reverse direction works: as a receiver (`emitter/bt3dg.py`) it decodes the ESP32's train
and beacon exactly as encoded.

## Video side

On a 240p CRT the game's frame period is the pair period divided by two. Frame-start events from the FPGA are jitter-free
in FPGA cycles; the estimator turns them into Bluetooth clock time with a regression over the controller's `Read_Clock`
samples (fastest third by round trip) and a long-window estimate of the FPGA-to-host crystal ratio (the announced period is
then within a few ppm, which keeps a lock for minutes).
