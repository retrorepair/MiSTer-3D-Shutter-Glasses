#!/usr/bin/env python3
"""Forward the SMS core's 3-D glasses events to a USB emitter.

Runs on the MiSTer (Linux, as root). The SMS core (OSD > 3D Glasses > USB sync output) publishes one
event per game write to $FFF8-$FFFB into a 64-entry ring in DDR3 at physical address 0x3DFFF000
(entry n = sequence number mod 64, 64 bytes per entry, only the first 64-bit word is used).
The daemon sends one byte per event over USB serial:

    'L'  left lens open now        'R'  right lens open now        '0'  no 3-D game running

Entry word (little endian, see rtl/glasses3d.sv):
    bits 63:48 sequence, 47:40 flags, 39:32 magic 0x5D, 31:0 core clock cycle counter at the event
    flags: bit0 left open, bit1 3-D active, bit2 PAL, bit3 output enabled, bit4 frame-start event (ignored here)

Usage:
    mister_glasses_daemon.py                  # find /dev/ttyACM* and forward
    mister_glasses_daemon.py --dev /dev/ttyACM0
    mister_glasses_daemon.py --monitor        # no dongle: print events and the measured delivery lag
"""
import argparse
import glob
import mmap
import os
import struct
import sys
import termios
import time

PHYS_ADDR = 0x3DFFF000
ENTRIES = 64
STRIDE = 64
MAGIC = 0x5D
WATCHDOG_S = 0.30                    # no event for this long while active -> report '0'
CLK_NTSC = 53693175.0                # core clock, Hz
CLK_PAL = 53203425.0
CLK_FAST = 6.25e6 * (8 + 3358154979 / 2 ** 32)   # +2.2% glasses sync clock, flags bit5
CLK_VB = 40000000.0                              # Virtual Boy core clock, flags bit6


def open_ring():
    fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
    return mmap.mmap(fd, ENTRIES * STRIDE, mmap.MAP_SHARED, mmap.PROT_READ, offset=PHYS_ADDR)


def read_ring(ring):
    """All 64 first-words as (seq, flags, magic, ts) tuples."""
    out = []
    for i in range(ENTRIES):
        ts, magic, flags, seq = struct.unpack_from('<IBBH', ring, i * STRIDE)
        out.append((seq, flags, magic, ts))
    return out


def open_serial(path):
    fd = os.open(path, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    attrs[0] = attrs[1] = attrs[3] = 0                      # raw
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    return fd


def find_serial():
    ports = sorted(glob.glob('/dev/ttyACM*'))
    return ports[0] if ports else None


def realtime():
    try:
        os.sched_setaffinity(0, {1})
        os.sched_setscheduler(0, os.SCHED_FIFO, os.sched_param(20))
    except (AttributeError, OSError, PermissionError):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dev', help='USB serial device of the emitter (default: first /dev/ttyACM*)')
    ap.add_argument('--monitor', action='store_true', help='print events, do not talk to a dongle')
    args = ap.parse_args()

    ring = open_ring()
    realtime()

    seen = [read_ring(ring)[i] for i in range(ENTRIES)]   # ignore whatever a previous run left behind
    last_ts = None
    unwrapped = 0.0
    offset_min = None
    lag_samples = []
    ser = None
    sent = None
    last_event = time.monotonic()

    def send(ch):
        nonlocal ser
        if args.monitor:
            return
        for _ in range(2):
            if ser is None:
                path = args.dev or find_serial()
                if not path:
                    return
                try:
                    ser = open_serial(path)
                    print('emitter on', path, flush=True)
                except OSError:
                    ser = None
                    return
            try:
                os.write(ser, ch.encode())
                return
            except OSError:
                try:
                    os.close(ser)
                except OSError:
                    pass
                ser = None

    print('watching the DDR3 event ring at 0x%08X' % PHYS_ADDR, flush=True)
    while True:
        now = time.monotonic()
        cur = read_ring(ring)
        new = [c for c, o in zip(cur, seen) if c != o and c[2] == MAGIC]
        if new:
            seen = cur
            # oldest first: order by the modular distance of the timestamp from the last one handled
            base = last_ts if last_ts is not None else min(n[3] for n in new)
            new.sort(key=lambda n: (n[3] - base) & 0xFFFFFFFF)
            for seq, flags, magic, ts in new:
                if flags & 0x10:
                    continue                  # frame-start events are for the Bluetooth emitter; the IR path wants the write instants
                clk = CLK_VB if flags & 0x40 else (CLK_FAST if flags & 0x20 else (CLK_PAL if flags & 4 else CLK_NTSC))
                if last_ts is not None:
                    unwrapped += ((ts - last_ts) & 0xFFFFFFFF) / clk
                last_ts = ts
                active = bool(flags & 2)
                out = ('L' if flags & 1 else 'R') if active else '0'
                lag = now - unwrapped
                offset_min = lag if offset_min is None else min(offset_min, lag)
                lag_samples.append((lag - offset_min) * 1000.0)
                last_event = now
                if args.monitor:
                    print('%.4f seq=%d flags=0x%02X %s  lag %.2f ms' % (now, seq, flags, out, lag_samples[-1]), flush=True)
                    if len(lag_samples) >= 120:
                        s = sorted(lag_samples)
                        print('  delivery lag over the last %d events: median %.2f ms, p90 %.2f ms, max %.2f ms'
                              % (len(s), s[len(s) // 2], s[int(len(s) * 0.9)], s[-1]), flush=True)
                        lag_samples.clear()
                if out != sent or out != '0':
                    send(out)
                    sent = out
        elif sent in ('L', 'R') and now - last_event > WATCHDOG_S:
            send('0')
            sent = '0'
            if args.monitor:
                print('%.4f watchdog -> 0' % now, flush=True)

        time.sleep(0.00005)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
