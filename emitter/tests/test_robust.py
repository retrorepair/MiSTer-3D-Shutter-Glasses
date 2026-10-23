"""Frame events with a dropout and an eye-order flip: the period estimate must stay exact and the lenses must swap once."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from bt3d_timing import EventClock, frame_fit, beacon_fields, CLK_FAST, TICK_US
from mister_bt3d import GridLock


class CM:
    fit = True
    rate = 3200.0

    def ticks_at(self, t):
        return 1000.0 + t * 3200.0


CLK = CLK_FAST
F_CYC = 896000                       # exact cycles per video frame (an integer in the core)
F = F_CYC / CLK                      # seconds
DROP_FROM, DROP_TO = 1000, 1030      # frames without events (the game left 3D mode for a moment)
FLIP_AT = 2000                       # from here the left eye is on the other frames (two frames of one eye in a row)

cm = CM()
ev = EventClock()
g = GridLock()
swap_log = []
periods = []
pair_log = []
nxt_beacon = 5.0
k = 0
while k < 3200:
    T = k * F
    if not (DROP_FROM <= k < DROP_TO):
        left = (k % 2 == 0) if k < FLIP_AT else ((k + 1) % 2 == 0)
        ts = (k * F_CYC) & 0xFFFFFFFF
        flags = 0x20 | 0x10 | 0x08 | 0x02 | (1 if left else 0)
        ev.add(ts, flags, 100.0 + T + 0.0005)
    while nxt_beacon <= T:
        now = 100.0 + nxt_beacon
        fit = frame_fit(ev.left_frame_starts()) if ev.uses_frames else None
        if fit and ev.pair_seconds:
            per_s = ev.pair_seconds * ev.host_per_fpga
            fields = beacon_fields(fit[0], per_s, cm)
            out = g.apply(fields, cm, now, 5.0, 300.0, settled=ev.host_per_fpga != 1.0, epoch=ev.epoch)
            periods.append(out[6] + out[7] / 256.0)
            swap_log.append((round(nxt_beacon, 2), g.swap))
            pair_log.append(ev.pair_cycles)
        nxt_beacon += 0.08
    k += 1

changes = [(t, s) for (t, s), (_, s0) in zip(swap_log[1:], swap_log) if s != s0]
print('pair cycles:', set(pair_log), '(expected %d)' % (2 * F_CYC))
print('swap changes:', changes, '(expected one, just after %.1f s)' % (FLIP_AT * F))
print('announced period spread: %.3f us (%.1f ppm)' % (max(periods) - min(periods), (max(periods) - min(periods)) / periods[0] * 1e6))
assert set(pair_log) == {2.0 * F_CYC}, 'the pair period must be exact'
assert len(changes) == 1 and FLIP_AT * F < changes[0][0] < FLIP_AT * F + 2.0, 'one swap, soon after the flip'
assert (max(periods) - min(periods)) / periods[0] < 10e-6, 'the announced period must not move'
print('PASS')
