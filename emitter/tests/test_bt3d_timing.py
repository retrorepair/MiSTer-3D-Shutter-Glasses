"""Simulate noisy events + noisy Bluetooth clock reads and check the phase the beacon would announce."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from bt3d_timing import ClockMap, EventClock, frame_fit, beacon_fields, TICK_US, CLK_NTSC

random.seed(7)

P_TRUE = 2 / 59.9227              # left+right frame pair (s)
FPGA_PPM = +25e-6
BT_PPM = -15e-6
HOST_T0 = 12345.678               # host monotonic offset
BT_RATE = 3200.0 * (1 + BT_PPM)   # true ticks per true second
BT_OFFSET = 0x0123456


def true_clk(T):
    return BT_OFFSET + BT_RATE * T


def run(duration=40.0, delay=(0.0001, 0.0012), rtt=(0.001, 0.004), verbose=True, unit_div=1):
    ev = EventClock()
    cm = ClockMap()
    errors = []
    next_clk = 0.0
    next_beacon = 3.0
    T = 0.0
    k = 0
    last_event_T = -1
    events = []                    # (T_event, eye)
    # build the event stream: L at k*P, R at k*P + P/2
    t = 0.0
    while t < duration:
        events.append((t, 1))
        events.append((t + P_TRUE / 2, 0))
        t += P_TRUE
    events.sort()
    ei = 0
    now = 0.0
    while now < duration:
        # deliver events whose arrival time has come
        while ei < len(events):
            Te, eye = events[ei]
            arr = Te + random.uniform(*delay)
            if arr > now:
                break
            ts = int(Te * CLK_NTSC * (1 + FPGA_PPM)) & 0xFFFFFFFF
            flags = 0x1A | eye            # frame event, active, enabled
            ev.add(ts, flags, HOST_T0 + arr)
            ei += 1
        if now >= next_clk:
            r = random.uniform(*rtt)
            read_T = now + r * random.uniform(0.3, 0.7)
            clk28 = int(true_clk(read_T) / unit_div) & 0x0FFFFFFF
            cm.add(HOST_T0 + now + r / 2, r, clk28)
            next_clk += 0.25
        if now >= next_beacon and cm.fit:
            fit = frame_fit(ev.left_frame_starts())
            if fit:
                ref_t, per = fit
                f = beacon_fields(ref_t, per * ev.host_per_fpga, cm, 0, 0, 0, False, 0.0)       # sync instant = the frame start: compare the clock estimate
                clk, phase, lo, lc, ro, rc, p_int, frac = f
                announced = clk + phase / TICK_US              # ticks
                # truth: the newest left-eye frame at or before ref_t, in the controller's own clock
                n_true = round((ref_t - HOST_T0) / P_TRUE)     # frame index of the reference
                truth = true_clk(n_true * P_TRUE)
                err = (announced - (truth % (1 << 28))) * TICK_US
                if err > (1 << 27) * TICK_US: err -= (1 << 28) * TICK_US
                if err < -(1 << 27) * TICK_US: err += (1 << 28) * TICK_US
                errors.append((announced, truth, err, p_int + frac / 256.0))
            next_beacon += 0.08
        now += 0.0005
    return errors


if __name__ == '__main__':
    for label, kw in (('typical', {}), ('worse link', dict(delay=(0.0001, 0.003), rtt=(0.002, 0.012))),
                      ('ESP32 units', dict(unit_div=2))):
        res = run(duration=150.0, **kw)
        # frame-index ambiguity: compare modulo the period
        P_ticks = P_TRUE * BT_RATE
        errs = []
        for ann, truth, err, p in res:
            d = ((ann - truth) % P_ticks)
            if d > P_ticks / 2: d -= P_ticks
            errs.append(d * TICK_US)
        errs = errs[40:]               # let the estimators warm up (~3 s)
        rms = math.sqrt(sum(e * e for e in errs) / len(errs))
        spread = max(errs) - min(errs)
        per = sum(p for *_, p in res[-400:]) / len(res[-400:])      # the last 30 s, once the crystal-ratio estimate has settled
        true_p_us = P_TRUE * BT_RATE * TICK_US
        print('%-11s phase error (in the controller clock): mean %+7.1f us, rms about the mean %6.1f us, peak-to-peak %6.1f us; '
              'announced period %.3f us (true %.3f, error %.2f ppm)'
              % (label, sum(errs) / len(errs), math.sqrt(sum((e - sum(errs) / len(errs)) ** 2 for e in errs) / len(errs)),
                 spread, per, true_p_us, (per / true_p_us - 1) * 1e6))
