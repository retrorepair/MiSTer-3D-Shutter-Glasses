"""Timing estimators for the MiSTer Bluetooth 3D emitter (pure Python, no hardware access).

Two things have to be related to produce a beacon the glasses can follow:

* the game's left-eye frames (events from the FPGA, timestamped by the FPGA clock and delivered to Linux
  with a small variable delay), and
* the Bluetooth controller's native clock (read over HCI with a variable round-trip time).

Both are noisy by up to a millisecond but extremely regular underneath, so a regression over a few
dozen samples recovers the phase to roughly 0.1 ms.
"""
import math
from collections import deque

TICK_US = 312.5          # Bluetooth native clock tick (3.2 kHz)
CLK_NTSC = 53693175.0    # SMS core clock, Hz (flags bit2 = PAL)
CLK_PAL = 53203425.0
CLK_FAST = 6.25e6 * (8 + 3358154979 / 2 ** 32)    # the +2.2% glasses sync clock (flags bit5), see SMS.sv
CLK_GROOVY = 82753648.0                           # Groovy core clk_sys (flags bit7)
CLK_VB = 40000000.0                              # Virtual Boy core clk_sys (flags bit6)


def linfit(xs, ys):
    """Least squares y = a + b*x."""
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        return my, 0.0
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    return my - b * mx, b


class ClockMap:
    """host monotonic time (s) -> Bluetooth native clock (ticks, unwrapped), from Read_Clock samples."""

    def __init__(self, keep=1200):
        self.samples = deque(maxlen=keep)     # (t_mid, rtt, ticks): 5 minutes at 4 per second
        self.last = None
        self.base_t = None
        self.fit = None                       # (a, b): reported units = a + b * (t - base_t)
        self.scale = 1                        # native 312.5 us ticks per reported unit (an ESP32 reports 625 us units)
        self.rms_us = None

    def add(self, t_mid, rtt, clk28):
        if self.last is None:
            ticks = float(clk28)
        else:
            ticks = self.last + ((clk28 - int(self.last)) & 0x0FFFFFFF)
        self.last = ticks
        if self.base_t is None:
            self.base_t = t_mid
        self.samples.append((t_mid, rtt, ticks))
        self._refit()

    def _refit(self):
        if len(self.samples) < 8:
            return
        rtts = sorted(s[1] for s in self.samples)
        cut = rtts[max(3, len(rtts) // 3)]            # keep the fastest third: smallest asymmetry
        good = [s for s in self.samples if s[1] <= cut]
        if len(good) < 6:
            return
        xs = [s[0] - self.base_t for s in good]
        ys = [s[2] for s in good]
        a, b = linfit(xs, ys)
        self.fit = (a, b)
        self.scale = 2 if b < 2400 else 1       # about 1600 units/s -> units of two native ticks
        res = [(y - (a + b * x)) * TICK_US * self.scale for x, y in zip(xs, ys)]
        self.rms_us = math.sqrt(sum(r * r for r in res) / len(res))

    def ticks_at(self, t):
        """native Bluetooth clock ticks (312.5 us) at host time t"""
        a, b = self.fit
        # readings are truncated, so the true clock is on average half a reported unit later than the fit
        return self.scale * (a + 0.5 + b * (t - self.base_t))

    @property
    def rate(self):
        """native ticks per host second (about 3200)"""
        return self.fit[1] * self.scale if self.fit else None


class EventClock:
    """Turns ring events (FPGA cycle counter + arrival time) into host-time instants of left-eye frames.

    Frame events (flags bit4, sent at the start of each picture) have exact video timing and are preferred;
    write events (the instant the game flips the eye, jittery by up to a millisecond) are the fallback for an
    older core."""

    WRITE_TO_FRAME_US = 4400.0         # the game writes in the vertical blanking interval, the picture starts after it

    def __init__(self, window=72):
        self.last_ts = None
        self.fpga_s = 0.0
        self.offsets = deque(maxlen=150)      # arrival - fpga time, delay >= 0 on top of a constant
        self.left_frames = deque(maxlen=window)
        self.left_writes = deque(maxlen=window)
        self.last_event_t = None
        self.last_frame_event_t = None
        self.active = False
        self.clk_prev = None
        self.buckets = deque(maxlen=300)      # (fpga second, smallest arrival - fpga offset in that second)
        self.bucket_id = None
        self.bucket_min = None
        self.cycles = 0                       # FPGA cycles since the first event (exact)
        self.prev_frame_cycles = None
        self.prev_frame_eye = None
        self.frame_deltas = deque(maxlen=60)  # cycles between consecutive frame events: exactly half a left+right pair
        self.epoch = 0                        # +1 whenever the left-eye frames moved to the other half of the pair period

    def add(self, ts, flags, arrival):
        clk = CLK_GROOVY if flags & 0x80 else CLK_VB if flags & 0x40 else (CLK_FAST if flags & 0x20 else (CLK_PAL if flags & 4 else CLK_NTSC))
        if clk != self.clk_prev:              # the core clock was switched: earlier offsets no longer line up
            self.offsets.clear()
            self.buckets.clear()
            self.bucket_id = None
            self.clk_prev = clk
        if self.last_ts is not None:
            d = (ts - self.last_ts) & 0xFFFFFFFF
            if d > 0x80000000:                # an older timestamp than one already seen: a damaged read, drop it
                return
            self.fpga_s += d / clk
            self.cycles += d
        self.last_ts = ts
        self.offsets.append(arrival - self.fpga_s)
        bid = int(self.fpga_s)
        if bid != self.bucket_id:
            if self.bucket_id is not None:
                self.buckets.append((self.bucket_id + 0.5, self.bucket_min))
            self.bucket_id = bid
            self.bucket_min = arrival - self.fpga_s
        else:
            self.bucket_min = min(self.bucket_min, arrival - self.fpga_s)
        self.last_event_t = arrival
        self.active = bool(flags & 2)
        if not self.active:
            self.left_frames.clear()
            self.left_writes.clear()
        elif flags & 0x10:
            self.last_frame_event_t = arrival
            eye = flags & 1
            if self.prev_frame_cycles is not None:
                delta = self.cycles - self.prev_frame_cycles
                med = self._median_delta()
                regular = med is None or abs(delta - med) <= 0.02 * med
                if regular:
                    self.frame_deltas.append(delta)
                if not regular or eye == self.prev_frame_eye:
                    # a dropout, or two frames of one eye in a row: the game's eye order moved by a frame, so the
                    # left-eye frames collected so far belong to the other half of the pair period
                    self.left_frames.clear()
                    self.epoch += 1
            self.prev_frame_cycles = self.cycles
            self.prev_frame_eye = eye
            if flags & 1:
                self.left_frames.append(self.fpga_s)
        elif flags & 1:
            self.left_writes.append(self.fpga_s)

    def _median_delta(self):
        if len(self.frame_deltas) < 8:
            return None
        d = sorted(self.frame_deltas)
        return d[len(d) // 2]

    @property
    def pair_cycles(self):
        """FPGA cycles in one left+right pair: twice the median spacing of consecutive frame events.  Exact (the core's video
        timing is an integer number of cycles), and a dropout or an eye-order flip cannot disturb a median over 60 frames."""
        med = self._median_delta()
        return None if med is None else 2.0 * med

    @property
    def pair_seconds(self):
        pc = self.pair_cycles
        return None if pc is None or self.clk_prev is None else pc / self.clk_prev

    @property
    def host_per_fpga(self):
        """Host seconds per FPGA second (1 + a few tens of ppm).  The game's period is exact in FPGA cycles, but the
        glasses count Bluetooth time, so the ratio between the two crystals matters: any error here is a steady drift of
        the shutter windows against the picture.  Taken from the slope of the smallest arrival delays over a few minutes."""
        if len(self.buckets) < 20:
            return 1.0
        xs = [b[0] for b in self.buckets]
        ys = [b[1] for b in self.buckets]
        slope = linfit(xs, ys)[1]
        return 1.0 + max(-3e-4, min(3e-4, slope))

    @property
    def uses_frames(self):
        return len(self.left_frames) >= 8 and self.last_frame_event_t is not None and             (self.last_event_t - self.last_frame_event_t) < 0.5

    def left_frame_starts(self):
        """Host-time instants at which a left-eye picture starts."""
        off = min(self.offsets)
        if self.uses_frames:
            return [t + off for t in self.left_frames]
        return [t + off + self.WRITE_TO_FRAME_US * 1e-6 for t in self.left_writes]


def frame_fit(times):
    """Instants of left-eye frames -> (reference instant of the newest one, period in s), or None."""
    if len(times) < 8:
        return None
    d = sorted(b - a for a, b in zip(times, times[1:]))
    p0 = d[len(d) // 2]                                  # median spacing: one left+right frame pair
    if p0 <= 0:
        return None
    ks = [round((t - times[0]) / p0) for t in times]
    ys = [t - times[0] for t in times]
    c0, p = linfit(ks, ys)
    # reject outliers (anything more than 0.3 ms off the line) and fit again
    keep = [(k, y) for k, y in zip(ks, ys) if abs(y - (c0 + p * k)) < 3e-4]
    if 8 <= len(keep) < len(ks):
        ks = [k for k, _ in keep]
        ys = [y for _, y in keep]
        c0, p = linfit(ks, ys)
    k_last = ks[-1]
    return times[0] + c0 + p * k_last, p


def beacon_fields(frame_t, period_s, cmap, lead_us=900.0, tail_us=2700.0, shift_us=0.0, swap=False, guard_us=1100.0, div=1, pann_us=0.0, centre=0.0,
                  window_us=13900.0):
    """Everything the 3D beacon needs, or None when the clock map is not ready.

    frame_t is the host time at which a left-eye picture starts.  Each eye's lens opens lead_us before its picture
    starts (inside the dark blanking interval, so the lens has finished opening when the picture appears) and starts
    closing tail_us before the next picture starts.  tail_us - lead_us is the dark gap between the two eyes.
    With window_us > 0 each lens is instead open for exactly that long (tail_us is ignored): the default 13.9 ms covers
    the 12.3 ms picture with 0.9 ms before it and 0.7 ms after it, and leaves guard_us of room on both sides of the
    windows inside the period so the OSD sync adjust (+-1 ms) can move them without leaving it.
    The beacon's frame-sync instant is placed guard_us before the first lens opens, so all four offsets lie inside the
    frame period (0 <= offset < period), like the shutter patterns that were verified on the glasses.
    Returns (clk28, phase_us, l_open, l_close, r_open, r_close, period_us, frac256)."""
    if cmap.fit is None:
        return None
    p_true = period_s * cmap.rate * TICK_US / div        # the real frame-pair period in Bluetooth-clock microseconds
    p_us = pann_us if pann_us > 0 else p_true            # what is announced (glasses refuse periods above ~32.7 ms)
    # With an announced period shorter than the real one the glasses' windows drift by (p_true - p_us) per period until
    # the next beacon is heard: put the sync instant so the error is zero `centre` periods after it.
    sync_t = frame_t + (shift_us - lead_us - guard_us + centre * (p_true - p_us)) * 1e-6
    clk_f = cmap.ticks_at(sync_t)
    clk = math.floor(clk_f)
    phase = int(round((clk_f - clk) * TICK_US))
    if phase > 312:
        phase = 312
    p_int = int(p_us)
    frac = int((p_us - p_int) * 256)
    half = p_true / 2.0                                  # the right picture really starts half a real period later
    gap = (half - window_us) if window_us > 0 else (tail_us - lead_us)          # dark time between the eyes
    lo = guard_us
    lc = guard_us + half - gap
    ro = guard_us + half
    rc = min(guard_us + p_true - gap, p_us - 400.0)    # every offset must stay inside the announced period
    if swap:
        lo, lc, ro, rc = ro, rc, lo, lc
    clamp = lambda v: max(0, min(65535, int(round(v))))
    return clk & 0x0FFFFFFF, phase, clamp(lo), clamp(lc), clamp(ro), clamp(rc), p_int, frac
