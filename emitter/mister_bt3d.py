#!/usr/bin/env python3
"""Bluetooth 3D emitter for the MiSTer SMS core: drives Bluetooth 3D shutter glasses from the game's eye timing.

Runs on the MiSTer (Linux, as root). It
  * reads the 3D events the core publishes in DDR3 (OSD > 3D Glasses > USB sync output: On),
  * relates the game's left-eye frames to the Bluetooth controller's native clock,
  * acts as a Bluetooth 3D display (Bluetooth SIG 3D Synchronization Profile, "Reference Protocol"):
    answers the glasses' inquiry, runs the synchronization train, and broadcasts the shutter timing beacon.

The controller can be an ESP32 running esp32_hci_bridge on a USB port (--dev /dev/ttyUSB0), or the MiSTer's own
Bluetooth adapter (--dev 0) if it is accepted by the glasses.  Pair the glasses once (hold their button until the LED
flashes, next to the emitter); afterwards a short press re-synchronizes them.

    mister_bt3d.py                      # ESP32 on /dev/ttyUSB*, otherwise hci0
    mister_bt3d.py --lead-us 2000 --tail-us 3800   # more dark margin around each eye switch (less ghosting, dimmer)
    mister_bt3d.py --shift-us -300      # move the shutter windows earlier (negative) or later (positive)
    mister_bt3d.py --swap               # exchange the eyes (picture looks inside-out)
"""
import argparse
import glob
import mmap
import os
import signal
import struct
import sys
import time
from types import SimpleNamespace

import bt3dd
from bt3dd import op, ok, open_hci, read_clock, beacon_payload, EV_NAMES
from bt3d_timing import ClockMap, EventClock, frame_fit, beacon_fields, TICK_US

PHYS_ADDR = 0x3DFFF000
ENTRIES = 64
STRIDE = 64
MAGIC = 0x5D
EVENT_TIMEOUT = 0.35            # no game event for this long -> both lenses open


def open_ring():
    fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
    return mmap.mmap(fd, ENTRIES * STRIDE, mmap.MAP_SHARED, mmap.PROT_READ, offset=PHYS_ADDR)


def read_ring(ring):
    out = []
    for i in range(ENTRIES):
        ts, magic, flags, seq = struct.unpack_from('<IBBH', ring, i * STRIDE)
        out.append((seq, flags, magic, ts))
    return out


def stable_entry(ring, i):
    """Read one ring entry until two consecutive reads agree: the ARM reads the FPGA's 64-bit write as two 32-bit
    loads, so a read that straddles the write can mix the new sequence number with the previous lap's timestamp."""
    prev = struct.unpack_from('<IBBH', ring, i * STRIDE)
    for _ in range(6):
        cur = struct.unpack_from('<IBBH', ring, i * STRIDE)
        if cur == prev:
            return cur
        prev = cur
    return prev


def default_cfg():
    return SimpleNamespace(cod=0x00043C, eir_flags=0x01, tx_power=4, path_loss=100, service_data=0,
                           train_interval=0x0080, csb_interval=0x0080, packet='DM1', retx=None, name='',
                           interlaced=False, train_timeout=5760000)       # one hour of synchronization train (slots); the ESP32 hangs on the spec maximum


def bring_up(h, cfg):
    bt3dd.setup(h, cfg)
    bt3dd.tune_scans(h)
    ok('Write_Scan_Enable (inquiry+page)', h.cmd(op(3, 0x1A), bytes([3]), 'scan')[0])
    bt3dd.csb_start(h, cfg)
    clear = beacon_payload(0, 0, 0xFFFF, 0, 0, 0, 0, 0)               # 2D mode until a game is running
    h.cmd(op(3, 0x76), struct.pack('<BBB', 1, 3, len(clear)) + clear, 'csb data')
    st, _ = h.cmd(op(1, 0x43), b'', 'start sync train')
    ok('Start_Synchronization_Train', st)


CTL_NUM = ('pann', 'centre', 'lead', 'tail', 'shift', 'div', 'bint', 'slew', 'dead', 'sold', 'clkscale', 'soff', 'slag')
CTL_BOOL = ('swap', 'grid', 'tstatic')


def apply_ctl(ctl, text):
    """Runtime settings from a text file: whitespace separated key=value (numbers; swap/grid 0 or 1; static=NAME:SECONDS,...)."""
    for tok in text.split():
        key, _, val = tok.partition('=')
        try:
            if key in CTL_NUM:
                ctl[key] = float(val)
            elif key in CTL_BOOL:
                ctl[key] = bool(int(val))
            elif key == 'static':
                ctl[key] = '' if val in ('', 'none', '0') else val
        except ValueError:
            pass


class GridLock:
    """Announce a perfectly regular beacon: window offsets and period frozen, sync instants exactly one period apart.
    The sync instant follows the measured one by slewing a few microseconds per beacon once it is off by more than a
    dead band, so estimation noise never reaches the glasses (the fixed test patterns that worked sat on an exact grid)."""

    def __init__(self):
        self.frozen = None
        self.origin = None
        self.err = 0.0
        self.settled = False
        self.t_refresh = 0.0

    def _ref(self, cm, now, period):
        """The latest grid instant (Bluetooth ticks) at or before now."""
        wrap = float(1 << 28)
        now_ticks = cm.ticks_at(now) % wrap
        n = int((((now_ticks - self.origin + wrap / 2) % wrap) - wrap / 2) // period)      # may be -1 right after a slew
        return (self.origin + n * period) % wrap

    def apply(self, fields, cm, now, slew_us, dead_us, settled=True):
        clk, phase, lo, lc, ro, rc, p_int, frac = fields
        wrap = float(1 << 28)
        target = clk + phase / TICK_US
        # The period is only re-read once the crystal-ratio estimate has settled, then every two minutes.  The grid is
        # kept where it is while the period is replaced, so the announced sync instants do not jump.
        if self.frozen is None or (settled and not self.settled) or (settled and now - self.t_refresh > 120.0):
            if self.frozen is not None and self.origin is not None:
                self.origin = self._ref(cm, now, (self.frozen[4] + self.frozen[5] / 256.0) / TICK_US)
            self.frozen = (lo, lc, ro, rc, p_int, frac)
            self.settled = settled
            self.t_refresh = now
        lo, lc, ro, rc, p_int, frac = self.frozen
        period = (p_int + frac / 256.0) / TICK_US
        if self.origin is None:
            self.origin = target
        else:
            e = ((target - self.origin + wrap / 2) % wrap) - wrap / 2
            e = e % period
            if e > period / 2:
                e -= period
            self.err += 0.03 * (e * TICK_US - self.err)          # average out the estimation noise (about 4 s)
            if abs(self.err) > dead_us:
                step = max(-slew_us, min(slew_us, self.err))
                self.origin += step / TICK_US
                self.err -= step
        ref = self._ref(cm, now, period)
        c = int(ref)
        return c & 0x0FFFFFFF, min(312, int(round((ref - c) * TICK_US))), lo, lc, ro, rc, p_int, frac


def restamp(fields, ctl, now, t_start):
    """Experiments on how the sync instant is stamped (the glasses accept the ESP32's raw half-rate clock but not the true one):
    sold = age it by whole periods, slag = let it fall behind real time at this fraction of real time (whole periods),
    clkscale / soff = scale / offset the clock value."""
    if not (ctl['sold'] > 0 or ctl['slag'] > 0 or ctl['clkscale'] != 1.0 or ctl['soff'] != 0.0):
        return fields
    p_us = fields[6] + fields[7] / 256.0
    p_ticks = p_us / TICK_US
    t = fields[0] + fields[1] / TICK_US
    if ctl['sold'] > 0:
        t -= round(ctl['sold'] * 1e6 / p_us) * p_ticks
    if ctl['slag'] > 0:
        t -= int(ctl['slag'] * (now - t_start) * 1e6 / p_us) * p_ticks
    t = t * ctl['clkscale'] + ctl['soff'] / TICK_US
    t %= float(1 << 28)
    c = int(t)
    return (c & 0x0FFFFFFF, min(312, int(round((t - c) * TICK_US)))) + tuple(fields[2:])


def find_controller(dev_arg):
    """The ESP32's serial port if it is present (a fixed --dev must exist; otherwise the first USB serial port)."""
    if dev_arg is not None:
        return dev_arg if os.path.exists(dev_arg) else None
    ports = sorted(glob.glob('/dev/ttyUSB*') + glob.glob('/dev/ttyACM*'))
    return ports[0] if ports else None


def reconnect(dev_arg, old):
    """The ESP32's USB connection dropped (cable knocked, power glitch): wait for it to come back and reopen it."""
    try:
        old.close()
    except Exception:
        pass
    while True:
        port = find_controller(dev_arg)
        if port:
            time.sleep(1.0)                   # let the USB enumeration settle
            try:
                print('controller back on %s: configuring it again' % port, flush=True)
                return open_hci(port)
            except (OSError, RuntimeError, TimeoutError) as exc:
                print('controller not ready yet (%s)' % exc, flush=True)
        time.sleep(1.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dev', default=None, help='ESP32 bridge port (/dev/ttyUSB0) or hci number; default: first /dev/ttyUSB*, else 0')
    ap.add_argument('--lead-us', dest='lead_us', type=float, default=1500.0, help='each lens opens this long before its picture starts')
    ap.add_argument('--tail-us', dest='tail_us', type=float, default=2700.0, help='each lens starts closing this long before the next picture (tail - lead = dark gap between the eyes)')
    ap.add_argument('--shift-us', dest='shift_us', type=float, default=0.0)
    ap.add_argument('--swap', action='store_true')
    ap.add_argument('--half-period', dest='half_period', action='store_true', help='experiment: announce one video frame as the glasses period')
    ap.add_argument('--seconds', type=float, default=0.0, help='stop after this long (0 = run until interrupted)')
    ap.add_argument('--raw-log', dest='raw_log', default=None)
    ap.add_argument('--beacon-ms', dest='beacon_ms', type=float, default=80.0,
                    help='beacon interval; the glasses re-check the beacon every 7 intervals, so a shorter one limits drift')
    ap.add_argument('--ctl-file', dest='ctl_file', default='/tmp/3d_ctl',
                    help='settings re-read whenever this file changes (pann= centre= lead= tail= shift= swap= div= grid= slew= dead= bint= static=)')
    args = ap.parse_args()

    def on_term(signum, frame):
        raise KeyboardInterrupt            # `kill` from the stop script: leave through the clean-up path

    signal.signal(signal.SIGTERM, on_term)

    dev = args.dev
    if dev is None:
        ports = sorted(glob.glob('/dev/ttyUSB*') + glob.glob('/dev/ttyACM*'))
        dev = ports[0] if ports else '0'
    bt3dd.RAW_LOG = args.raw_log
    print('controller:', dev, flush=True)
    h = open_hci(dev)
    cfg = default_cfg()
    cfg.csb_interval = max(2, int(round(args.beacon_ms * 1.6 / 2.0)) * 2)      # slots (0.625 ms), even
    for attempt in range(4):
        try:
            bring_up(h, cfg)
            break
        except (OSError, TimeoutError) as exc:
            print('starting the controller failed (%s): resetting it and trying again' % exc, flush=True)
            h = reconnect(args.dev, h)
    else:
        raise SystemExit('the controller does not start')
    ring = open_ring()

    seen = read_ring(ring)                      # ignore what a previous run left behind
    ev = EventClock()
    cm = ClockMap()
    seen_reboots = getattr(h, 'reboots', 0)
    t_start = time.monotonic()
    next_clock = 0.0
    next_beacon = 0.0
    next_stats = t_start + 2.0
    n_events = 0
    n_beacons = 0
    last_mode = None
    last_fields = None
    train_restarts = 0
    n_inq = 0
    n_pages = 0
    last_inq_print = 0.0
    ctl = dict(pann=0.0, centre=0.0, lead=args.lead_us, tail=args.tail_us, shift=args.shift_us, swap=args.swap,
               div=2.0 if args.half_period else 1.0, bint=args.beacon_ms, slew=5.0, dead=300.0, grid=True, static='',
               sold=0.0, clkscale=1.0, soff=0.0, slag=0.5, tstatic=False)
    ctl_mtime = None
    next_ctl = 0.0
    glock = GridLock()
    next_dump = 0.0
    warned_period = False
    st_phases = []
    st_cycle = 0.0
    st_t0 = 0.0
    st_idx = None
    st_pat = None
    st_glock = GridLock()
    st_origin = 0
    st_period = 0.0

    try:
        while args.seconds <= 0 or time.monotonic() - t_start < args.seconds:
            try:
                now = time.monotonic()

                # 0. runtime settings
                if now >= next_ctl:
                    next_ctl = now + 0.3
                    try:
                        mt = os.stat(args.ctl_file).st_mtime
                        if mt != ctl_mtime:
                            ctl_mtime = mt
                            apply_ctl(ctl, open(args.ctl_file).read())
                            glock = GridLock()
                            st_phases = []
                            for item in [x for x in ctl['static'].split(',') if x]:
                                nm, _, sec = item.partition(':')
                                bt3dd.preset(nm)
                                st_phases.append((nm, float(sec) if sec else 5.0))
                            st_cycle = sum(sec for _, sec in st_phases)
                            st_t0 = now
                            st_idx = None
                            last_mode = None
                            print('%7.1f s  settings: %s' % (now - t_start, ' '.join('%s=%s' % kv for kv in sorted(ctl.items()))), flush=True)
                    except (OSError, KeyError):
                        pass

                # 1. new game events from the DDR3 ring
                cur = read_ring(ring)
                changed = [i for i, (c, o) in enumerate(zip(cur, seen)) if c != o]
                if changed:
                    for i in changed:
                        ts_, mg_, fl_, sq_ = stable_entry(ring, i)
                        cur[i] = (sq_, fl_, mg_, ts_)
                new = [cur[i] for i in changed if cur[i][2] == MAGIC]
                if changed:
                    seen = cur
                if new:
                    base = ev.last_ts if ev.last_ts is not None else min(n[3] for n in new)
                    new.sort(key=lambda n: (n[3] - base) & 0xFFFFFFFF)
                    arrival = time.monotonic()
                    for seq, flags, magic, ts in new:
                        ev.add(ts, flags, arrival)
                        n_events += 1

                # 2. Bluetooth clock sample
                if now >= next_clock:
                    t0 = time.monotonic()
                    clk = read_clock(h)
                    t1 = time.monotonic()
                    cm.add((t0 + t1) / 2, t1 - t0, clk)
                    next_clock = now + 0.25

                # 3. beacon
                if now >= next_beacon:
                    fields = None
                    if st_phases:
                        # a fixed shutter pattern from bt3dd's test list, not tied to the game
                        pos = (now - st_t0) % st_cycle
                        idx = 0
                        while pos >= st_phases[idx][1]:
                            pos -= st_phases[idx][1]
                            idx += 1
                        if idx != st_idx:
                            st_idx = idx
                            st_glock = GridLock()
                            st_pat = bt3dd.preset(st_phases[idx][0])
                            st_period = st_pat[0] + st_pat[1] / 256.0
                            st_origin = read_clock(h)
                            print('%7.1f s  static pattern %s  period %d+%d/256 us, left %d..%d us, right %d..%d us'
                                  % (now - t_start, st_phases[idx][0], st_pat[0], st_pat[1], st_pat[2], st_pat[3], st_pat[4], st_pat[5]), flush=True)
                        if ctl['tstatic'] and cm.fit:
                            # the same fixed pattern, but the sync instants are in true Bluetooth ticks (3200 per second) and sit on
                            # an exact grid started now (the plain static patterns use the ESP32's raw half-rate clock)
                            tt = cm.ticks_at(now)
                            tc = int(tt)
                            tf = (tc & 0x0FFFFFFF, min(312, int(round((tt - tc) * TICK_US))), st_pat[2], st_pat[3], st_pat[4], st_pat[5], st_pat[0], st_pat[1])
                            payload = beacon_payload(*restamp(st_glock.apply(tf, cm, now, 0.0, 1e12), ctl, now, t_start))
                            mode = 'static %s (true clock)' % st_phases[idx][0]
                        else:
                            s_clk, s_phase = bt3dd.grid_reference(st_origin, read_clock(h), st_period)
                            payload = beacon_payload(s_clk, s_phase, st_pat[2], st_pat[3], st_pat[4], st_pat[5], st_pat[0], st_pat[1])
                            mode = 'static %s' % st_phases[idx][0]
                    else:
                        running = ev.last_event_t is not None and ev.active and (now - ev.last_event_t) < EVENT_TIMEOUT
                        if running and cm.fit:
                            fit = frame_fit(ev.left_frame_starts())
                            if fit:
                                per_s = fit[1] * ev.host_per_fpga
                                p_true_us = per_s * cm.rate * TICK_US / ctl['div']
                                pann = ctl['pann'] or (32700.0 if p_true_us > 32700.0 else 0.0)
                                if pann and not ctl['pann'] and not warned_period:
                                    warned_period = True
                                    print('%7.1f s  WARNING: the game\'s frame pair lasts %.0f us but the glasses accept at most about 32700 us: '
                                          'turn on OSD > 3D Glasses > Glasses sync clock +2.2%%, or the picture will roll' % (now - t_start, p_true_us), flush=True)
                                fields = beacon_fields(fit[0], per_s, cm, ctl['lead'], ctl['tail'], ctl['shift'], ctl['swap'],
                                                       div=int(ctl['div']), pann_us=pann, centre=ctl['centre'])
                                if fields and ctl['grid']:
                                    fields = glock.apply(fields, cm, now, ctl['slew'], ctl['dead'], settled=ev.host_per_fpga != 1.0)
                                if fields:
                                    fields = restamp(fields, ctl, now, t_start)
                        if fields:
                            last_fields = fields
                            payload = beacon_payload(*fields)
                            mode = '3D'
                        else:
                            payload = beacon_payload(0, 0, 0xFFFF, 0, 0, 0, 0, 0)          # both lenses open
                            mode = '2D'
                    h.cmd(op(3, 0x76), struct.pack('<BBB', 1, 3, len(payload)) + payload, 'csb data')
                    n_beacons += 1
                    if now >= next_dump:
                        next_dump = now + 5.0
                        c_now = cm.ticks_at(time.monotonic()) if not st_phases else read_clock(h)
                        c_ann = int.from_bytes(payload[0:4], 'little') + int.from_bytes(payload[4:6], 'little') / TICK_US
                        age_us = (((c_now - c_ann) + (1 << 27)) % (1 << 28) - (1 << 27)) * TICK_US
                        print('%7.1f s  beacon payload %s  (announced sync instant is %.0f us before the controller clock now)'
                              % (now - t_start, payload.hex(), age_us), flush=True)
                    next_beacon = now + ctl['bint'] / 1000.0
                    if mode != last_mode:
                        print('%7.1f s  beacon mode: %s%s%s' % (now - t_start, mode, ' (frame events)' if ev.uses_frames else ' (write events)',
                              '  (period %d + %d/256 us, left %d..%d us, right %d..%d us)'
                              % (fields[6], fields[7], fields[2], fields[3], fields[4], fields[5]) if fields else ''), flush=True)
                        last_mode = mode

                # 4. controller events
                e = h.pump(0.0005)
                while e:
                    code, data = e
                    if code == 0x4F:                          # synchronization train timed out: start another
                        st, _ = h.cmd(op(1, 0x43), b'', 'start sync train')
                        train_restarts += 1
                        print('%7.1f s  synchronization train ended (event status 0x%02X); restarted: status 0x%02X'
                              % (now - t_start, data[0] if data else 0xFF, st), flush=True)
                    elif code == 0x56:                        # something sent an inquiry and got our answer
                        n_inq += 1
                        if now - last_inq_print > 1.0:
                            last_inq_print = now
                            print('%7.1f s  inquiry answered (LAP %06X, total %d)' % (now - t_start, int.from_bytes(data[0:3], 'little'), n_inq), flush=True)
                    elif code == 0x54:
                        n_pages += 1
                        print('%7.1f s  the glasses paged us (sync trigger)' % (now - t_start), flush=True)
                    elif code not in (0x13, 0x55):
                        print('%7.1f s  %s' % (now - t_start, bt3dd.describe(code, data)), flush=True)
                    e = h.pump(0.0)

                if getattr(h, 'reboots', 0) > seen_reboots:
                    seen_reboots = h.reboots
                    print('%7.1f s  controller restarted: configuring it again' % (now - t_start), flush=True)
                    bring_up(h, cfg)
                    cm = ClockMap()

                # 5. status
                if now >= next_stats:
                    rate = cm.rate
                    print('%7.1f s  events %d (%.0f/s)  beacons %d  inquiries %d  pages %d  clock fit %s  mode %s%s' % (
                        now - t_start, n_events, n_events / max(1e-9, now - t_start), n_beacons, n_inq, n_pages,
                        ('%.1f us rms, %.2f ticks/s' % (cm.rms_us, rate)) if cm.rms_us is not None else 'warming up',
                        last_mode, ('  period %d+%d/256 us' % (last_fields[6], last_fields[7])) if last_fields and last_mode == '3D' else ''), flush=True)
                    next_stats = now + 5.0

                time.sleep(0.0004)
            except (OSError, TimeoutError) as exc:
                if not hasattr(h, 'hard_reset'):
                    raise
                print('%7.1f s  lost the controller (%s)' % (time.monotonic() - t_start, exc), flush=True)
                while True:
                    h = reconnect(args.dev, h)
                    try:
                        bring_up(h, cfg)
                        break
                    except (OSError, TimeoutError) as exc2:
                        print('configuring the controller failed (%s): retrying' % exc2, flush=True)
                cm = ClockMap()
                seen_reboots = getattr(h, 'reboots', 0)
                seen = read_ring(ring)
                next_clock = next_beacon = 0.0
                last_mode = None
    except KeyboardInterrupt:
        pass
    finally:
        try:
            if hasattr(h, 'hard_reset'):
                h.hard_reset()
            else:
                bt3dd.restore(h)              # give a Linux adapter back its normal state
        except OSError:
            pass                              # the controller is gone anyway


if __name__ == '__main__':
    main()
