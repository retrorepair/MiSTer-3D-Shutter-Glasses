#!/usr/bin/env python3
"""Act as a pair of Bluetooth 3D glasses ("3DG") with a second Bluetooth controller on the MiSTer.

Used to check what bt3dd.py really transmits, independently of the real glasses, following the
glasses' procedure in the Bluetooth 3D Synchronization Profile appendix 12:
  1. general inquiry, collect extended inquiry responses from devices with class 0x00043C/0x08043C
  2. receive the synchronization train of the chosen display (decoded and printed)
  3. receive the connectionless broadcast it announces (the 3D beacon, decoded and printed)

Run the transmitter on one adapter and this on the other, e.g.:
    python3 bt3dd.py beacon --dev 0 --seconds 60 &
    python3 bt3dg.py --dev 1
Needs a controller that supports Synchronization Scan / Connectionless Slave Broadcast receive.
EXPERIMENTAL.
"""
import argparse
import struct
import sys
import time

from bt3dd import open_hci, op, ok, EV_NAMES


def parse_eir(eir):
    out = []
    i = 0
    while i < len(eir) and eir[i]:
        ln = eir[i]
        out.append((eir[i + 1], bytes(eir[i + 2:i + 1 + ln])))
        i += ln + 1
    return out


def addr_str(b):
    return ':'.join('%02X' % x for x in reversed(b))


def inquiry(h, seconds):
    """General inquiry with EIR; returns {bdaddr(bytes): (cod, rssi, eir_fields)}."""
    ok('Write_Inquiry_Mode (extended)', h.cmd(op(3, 0x45), bytes([2]), 'inquiry mode')[0])
    st, _ = h.cmd(op(1, 0x01), bytes([0x33, 0x8B, 0x9E, int(seconds / 1.28) + 1, 0]), 'inquiry')
    ok('Inquiry', st)
    found = {}
    end = time.monotonic() + seconds + 2
    while time.monotonic() < end:
        ev = h.pump(0.5)
        if not ev:
            continue
        code, data = ev
        if code == 0x2F and len(data) >= 15:                      # extended inquiry result
            addr = bytes(data[1:7])
            cod = int.from_bytes(data[9:12], 'little')
            rssi = struct.unpack_from('<b', data, 14)[0]
            found[addr] = (cod, rssi, parse_eir(data[15:]))
        elif code == 0x01:                                         # inquiry complete
            break
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dev', default='1', help='hciN of the receiving adapter (default 1) or a serial port with an ESP32 HCI bridge, e.g. COM8')
    ap.add_argument('--seconds', type=float, default=60.0, help='how long to listen for the train/beacon')
    ap.add_argument('--inquiry', type=float, default=8.0)
    ap.add_argument('--target', help='BD_ADDR of the display (default: first 3D display found)')
    args = ap.parse_args()

    h = open_hci(args.dev)
    ok('Set_Event_Mask', h.cmd(op(3, 0x01), bytes([0xFF] * 8), 'event mask')[0])
    ok('Set_Event_Mask_Page_2', h.cmd(op(3, 0x63), bytes([0xFF] * 8), 'event mask 2')[0])

    print('inquiring for %.0f s ...' % args.inquiry)
    found = inquiry(h, args.inquiry)
    target = None
    for addr, (cod, rssi, eir) in found.items():
        is3d = cod in (0x00043C, 0x08043C) and any(t == 0xFF and d[:2] == bytes([0x0F, 0x00]) for t, d in eir)
        print('  %s class 0x%06X rssi %d  EIR %s%s' % (addr_str(addr), cod, rssi,
              ' '.join('%02X:%s' % (t, d.hex()) for t, d in eir), '   <-- 3D display' if is3d else ''))
        if is3d and (args.target is None or addr_str(addr) == args.target.upper()):
            target = target or addr
    if target is None:
        print('no 3D display answered the inquiry')
        return 1
    print('selected', addr_str(target))

    # synchronization scan: 103.75 ms window like legacy glasses
    params = target + struct.pack('<HHH', min(0xFFFF, int(args.seconds / 0.000625)), 0x00A6, 0x00C0)
    st, _ = h.cmd(op(1, 0x44), params, 'receive sync train')
    ok('Receive_Synchronization_Train', st)
    if st != 0:
        return 1

    t0 = time.monotonic()
    train = None
    while time.monotonic() - t0 < args.seconds:
        ev = h.pump(0.5)
        if not ev:
            continue
        code, d = ev
        if code == 0x50 and len(d) >= 29:
            status = d[0]
            print('%.1f s  SYNC TRAIN RECEIVED status 0x%02X' % (time.monotonic() - t0, status))
            if status == 0:
                train = dict(addr=bytes(d[1:7]), offset=struct.unpack_from('<I', d, 7)[0], afh=bytes(d[11:21]),
                             lt=d[21], next=struct.unpack_from('<I', d, 22)[0],
                             interval=struct.unpack_from('<H', d, 26)[0], service=d[28])
                print('  clock offset 0x%08X  LT_ADDR %d  next broadcast 0x%08X  interval %d slots (%.1f ms)  service data %d'
                      % (train['offset'], train['lt'], train['next'], train['interval'], train['interval'] * 0.625, train['service']))
                print('  AFH map', train['afh'].hex())
                break
        elif code != 0x13:
            print('%.1f s  %s %s' % (time.monotonic() - t0, EV_NAMES.get(code, 'event 0x%02X' % code), d.hex()))
    if train is None:
        print('no synchronization train received')
        return 2

    st = None
    for ptype in (0x0008, 0x0018, 0xCC18, 0x0010):
        for sup in (0x7D00, 0x1F40, 0x0400):
            params = (bytes([1]) + train['addr'] + bytes([train['lt']]) + struct.pack('<H', train['interval']) +
                      struct.pack('<II', train['offset'], train['next']) + struct.pack('<H', sup) +
                      bytes([0xFA, 0]) + struct.pack('<H', ptype) + train['afh'])
            st, _ = h.cmd(op(1, 0x42), params, 'receive csb')
            print('  Set_CSB_Receive packet types 0x%04X supervision 0x%04X -> status 0x%02X' % (ptype, sup, st))
            if st == 0:
                break
        if st == 0:
            break
    ok('Set_Connectionless_Slave_Broadcast_Receive', st)
    beacons = 0
    good_beacons = 0
    end = time.monotonic() + 15
    while time.monotonic() < end:
        ev = h.pump(0.5)
        if not ev:
            continue
        code, d = ev
        if code == 0x51 and len(d) >= 18:
            # BD_ADDR(6) LT_ADDR(1) clock(4) offset(4) | receive status(1) fragment(1) data length(1) data
            rx_status, frag, ln = d[15], d[16], d[17]
            data = bytes(d[18:18 + ln])
            beacons += 1
            if rx_status == 0 and len(data) >= 17 and good_beacons < 5:
                clk, ph, lo, lc, ro, rc, per, fr = struct.unpack_from('<IHHHHHHB', data)
                print('  beacon: frame sync clock 0x%07X +%d us, left %d..%d us, right %d..%d us, period %d + %d/256 us'
                      % (clk & 0x0FFFFFFF, ph, lo, lc, ro, rc, per, fr))
            if rx_status == 0 and len(data) >= 17:
                good_beacons += 1
            elif beacons <= 3:
                print('  csb receive event: receive status %d (0 = good), fragment %d, length %d' % (rx_status, frag, ln))
        elif code == 0x52:
            print('  csb receive timeout')
        elif code != 0x13:
            print('  %s %s' % (EV_NAMES.get(code, 'event 0x%02X' % code), d.hex()))
    print('beacon events in 15 s: %d, of which good (status 0, 17 bytes): %d (expected about %d)' % (beacons, good_beacons, int(15 / (train['interval'] * 0.000625))))
    return 0


if __name__ == '__main__':
    sys.exit(main())
