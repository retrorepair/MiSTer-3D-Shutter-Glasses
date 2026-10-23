#!/usr/bin/env python3
"""Act as a Bluetooth 3D display ("3DD") with a Bluetooth controller on the MiSTer.

Implements the display side of the Bluetooth SIG 3D Synchronization Profile and its Appendix 12
"Reference Protocol" (used by the 2011/12 Full HD 3D Glasses Initiative glasses) through raw HCI
commands: inquiry response with the 3D EIR data, synchronization train, and connectionless
broadcast of the shutter-timing beacon.  EXPERIMENTAL - written from the public spec.
Run as root on the MiSTer (needs a controller with Core 4.1 CSB support).

    bt3dd.py check                    verify every command is accepted, then restore the controller
    bt3dd.py assoc  [--seconds 60]    be discoverable as a 3D display and log glasses inquiring
    bt3dd.py beacon [--rate 59.94]    sync train + beacon with a fixed shutter pattern
                    [--seconds 120]   (--rate 29.97 is the SMS cadence: one frame = left + right)

Protocol variations for experiments (defaults follow the spec):
    --dev N            use hciN              --cod 0x08043C      class of device
    --eir-flags 0x01   byte 5 of the 3D EIR  --tx-power 4        TX power in the EIR (dBm, 0..127)
    --path-loss 100    path loss threshold   --service-data 0     service data in the sync train
    --train-interval 128   sync train interval (slots, 0.625 ms)  --csb-interval 128  beacon interval
    --packet DM1|DH1   beacon packet type    --retx N            broadcast retransmissions
    --train always|onpage                    --name TEXT         local name
    --interlaced       interlaced inquiry scan

The controller state it changes is restored on exit.
"""
import argparse
import os
import socket
import struct
import sys
import time

HCI_COMMAND, HCI_EVENT = 1, 4
EV_CMD_COMPLETE, EV_CMD_STATUS = 0x0E, 0x0F
EV_SYNC_TRAIN_COMPLETE, EV_PAGE_TIMEOUT, EV_INQ_RESP_NOTIF = 0x4F, 0x54, 0x56
MFR_BROADCOM = 0x000F

EV_NAMES = {0x03: 'connection-complete', 0x05: 'disconnection', 0x13: 'num-completed-packets',
            0x4E: 'triggered-clock-capture', 0x4F: 'sync-train-complete', 0x50: 'sync-train-received',
            0x54: 'peripheral-page-response-timeout', 0x56: 'inquiry-response-notification'}


def op(ogf, ocf):
    return (ogf << 10) | ocf


class HCIBase:
    """Command/event plumbing shared by the transports (raw HCI socket on Linux, H4 over a serial port)."""

    def __init__(self):
        self.events = []

    def cmd(self, opcode, params=b'', name='', timeout=2.0):
        self.send(struct.pack('<BHB', HCI_COMMAND, opcode, len(params)) + params)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            ev = self.pump(0.2)
            if ev is None:
                continue
            code, data = ev
            if code == EV_CMD_COMPLETE and len(data) >= 4 and struct.unpack_from('<H', data, 1)[0] == opcode:
                return data[3], data[3:]
            if code == EV_CMD_STATUS and len(data) >= 4 and struct.unpack_from('<H', data, 2)[0] == opcode:
                return data[0], data[:1]
            self.events.append(ev)
        raise TimeoutError('no response to %s (0x%04X)' % (name, opcode))


class HCISocket(HCIBase):
    """A Bluetooth controller of this Linux machine (hciN)."""

    def __init__(self, dev=0):
        HCIBase.__init__(self)
        self.s = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_RAW, socket.BTPROTO_HCI)
        flt = struct.pack('<LLLHH', 1 << HCI_EVENT, 0xFFFFFFFF, 0xFFFFFFFF, 0, 0)   # struct hci_filter, 16 bytes
        self.s.setsockopt(socket.SOL_HCI, socket.HCI_FILTER, flt)
        self.s.bind((dev,))

    def send(self, pkt):
        self.s.send(pkt)

    def pump(self, timeout):
        """Read one event packet -> (code, params), or None on timeout."""
        self.s.settimeout(timeout)
        try:
            pkt = self.s.recv(300)
        except socket.timeout:
            return None
        if len(pkt) < 3 or pkt[0] != HCI_EVENT:
            return None
        return pkt[1], pkt[3:3 + pkt[2]]


class RawSerialPort:
    """Minimal pyserial stand-in for Linux boxes without it (the MiSTer): raw 8N1 port with timeouts."""

    def __init__(self, path, baud=921600):
        import fcntl
        import termios
        self._fcntl, self._termios = fcntl, termios
        self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        speed = getattr(termios, 'B%d' % baud)
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL | speed
        attrs[3] = 0
        attrs[4] = speed
        attrs[5] = speed
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        self.timeout = 0.05

    def _modem(self, bit, on):
        t = self._termios
        self._fcntl.ioctl(self.fd, t.TIOCMBIS if on else t.TIOCMBIC, struct.pack('I', bit))

    dtr = property(None, lambda self, v: self._modem(self._termios.TIOCM_DTR, v))
    rts = property(None, lambda self, v: self._modem(self._termios.TIOCM_RTS, v))

    def write(self, data):
        import select
        view = memoryview(data)
        while len(view):
            select.select([], [self.fd], [], 1.0)
            n = os.write(self.fd, view)
            view = view[n:]

    def close(self):
        os.close(self.fd)

    def read(self, n):
        import select
        r, _, _ = select.select([self.fd], [], [], self.timeout)
        if not r:
            return b''
        try:
            return os.read(self.fd, n)
        except BlockingIOError:
            return b''


class HCISerial(HCIBase):
    """An ESP32 running esp32_hci_bridge (H4 over its USB serial port, 921600 baud)."""

    def __init__(self, port, baud=921600):
        HCIBase.__init__(self)
        try:
            import serial
            self.ser = serial.Serial(port, baud, timeout=0.05)
        except ImportError:
            self.ser = RawSerialPort(port, baud)
        self.ser.dtr = False
        self.ser.rts = True                 # EN low ...
        time.sleep(0.1)
        self.ser.rts = False                # ... and high: reboot the ESP32
        buf = b''
        end = time.monotonic() + 10
        while time.monotonic() < end and b'HCI-BRIDGE READY' not in buf:
            buf += self.ser.read(256)
        if b'HCI-BRIDGE READY' not in buf:
            raise RuntimeError('no HCI bridge on %s (flash esp32_hci_bridge first)' % port)
        self.rx = bytearray()
        self.rawlog = open(RAW_LOG, 'wb') if RAW_LOG else None
        self.reboots = 0
        self.reset_reason = None
        # The ESP32 may still be rebooting from an earlier reset: wait until it really answers a command.
        for attempt in range(4):
            time.sleep(0.4)
            self.rx.clear()
            try:
                st, _ = self.cmd(0x0C03, b'', 'HCI_Reset', timeout=1.5)
                if st == 0:
                    break
            except TimeoutError:
                pass
            self.hard_reset()
            end = time.monotonic() + 5
            buf = b''
            while time.monotonic() < end and b'HCI-BRIDGE READY' not in buf:
                buf += self.ser.read(256)
        else:
            raise RuntimeError('the ESP32 HCI bridge on %s does not answer' % port)
        self.reboots = 0

    def send(self, pkt):
        self.ser.write(pkt)

    def close(self):
        self.ser.close()
        if self.rawlog:
            self.rawlog.close()

    def _parse(self):
        b = self.rx
        while b and b[0] != HCI_EVENT:
            del b[0]
        if len(b) >= 3 and len(b) >= 3 + b[2]:
            pkt = bytes(b[:3 + b[2]])
            del b[:3 + b[2]]
            return pkt[1], pkt[3:]
        return None

    def pump(self, timeout):
        end = time.monotonic() + timeout
        while True:
            ev = self._parse()
            if ev:
                return ev
            left = end - time.monotonic()
            if left <= 0:
                return None
            self.ser.timeout = min(left, 0.05)
            d = self.ser.read(256)
            if d:
                if self.rawlog:
                    self.rawlog.write(d)
                    self.rawlog.flush()
                self.rx += d
                self._check_banner()

    def hard_reset(self):
        """Reboot the ESP32 (the controller's CSB disable path can assert; a reset is cleaner)."""
        self.ser.dtr = False
        self.ser.rts = True
        time.sleep(0.1)
        self.ser.rts = False

    def _check_banner(self):
        k = self.rx.find(b'ASSERT_ERR(')
        if k >= 0:
            e = self.rx.find(bytes([10]), k)
            if e > 0:
                print('!! ESP32 controller assertion: ' + bytes(self.rx[k:e]).decode('ascii', 'replace').strip(), flush=True)
                del self.rx[k:e]
        tag = b'HCI-BRIDGE READY reset='
        i = self.rx.find(tag)
        if i >= 0:
            j = self.rx.find(bytes([10]), i)
            if j < 0:
                return
            self.reboots += 1
            self.reset_reason = int(bytes(self.rx[i + len(tag):j]).strip() or b'-1')
            print('!! ESP32 rebooted (reset reason %d: 1 power-on, 3 software, 4 panic, 5/6/7 watchdog, 9 brownout)' % self.reset_reason, flush=True)
            del self.rx[:j + 1]


RAW_LOG = None           # path: keep every byte received from an ESP32 bridge (to read its crash messages)


def open_hci(spec):
    """'0', '1', ... -> hciN of this machine; anything else (COM8, /dev/ttyUSB0) -> ESP32 HCI bridge."""
    spec = str(spec)
    return HCISocket(int(spec)) if spec.isdigit() else HCISerial(spec)


HCI = open_hci


def describe(code, data):
    name = EV_NAMES.get(code, 'event 0x%02X' % code)
    if code == EV_INQ_RESP_NOTIF and len(data) >= 4:
        return '%s (inquiry access code LAP %06X, raw rssi byte 0x%02X)' % (name, int.from_bytes(data[0:3], 'little'), data[3])
    return '%s %s' % (name, data.hex())


def eir_3dd(cfg):
    """Reference Protocol 3D Information + TX power (spec table 12.3 / 5.3)."""
    mfr = bytes([0x06, 0xFF, MFR_BROADCOM & 0xFF, MFR_BROADCOM >> 8, 0x00, cfg.eir_flags & 0xFF, cfg.path_loss & 0xFF])
    txp = bytes([0x02, 0x0A, cfg.tx_power & 0xFF])
    eir = mfr + txp
    if cfg.name:
        n = cfg.name.encode()[:20]
        eir += bytes([len(n) + 1, 0x09]) + n
    return eir.ljust(240, bytes([0]))


def beacon_payload(clk, phase_us, l_open, l_close, r_open, r_close, period_us, frac256):
    """Reference Protocol beacon (spec tables 12.11/12.13), 17 bytes."""
    return struct.pack('<IHHHHHHB', clk & 0x0FFFFFFF, phase_us, l_open, l_close, r_open, r_close,
                       period_us, frac256)


def ok(label, status):
    print('  %-38s %s' % (label, 'ok' if status == 0 else 'FAILED status 0x%02X' % status))
    return status == 0


ORIG_NAME = []          # the controller's local name before we changed it


def packet_mask(cfg):
    return {'DM1': 0x0008, 'DH1': 0x0010}[cfg.packet]


def setup(h, cfg):
    good = True
    good &= ok('Set_Event_Mask', h.cmd(op(3, 0x01), bytes([0xFF] * 8), 'event mask')[0])
    good &= ok('Set_Event_Mask_Page_2', h.cmd(op(3, 0x63), bytes([0xFF] * 8), 'event mask 2')[0])
    good &= ok('Write_Class_of_Device 0x%06X' % cfg.cod, h.cmd(op(3, 0x24), cfg.cod.to_bytes(3, 'little'), 'cod')[0])
    good &= ok('Write_Extended_Inquiry_Response', h.cmd(op(3, 0x52), bytes([1]) + eir_3dd(cfg), 'eir')[0])
    if cfg.name:
        st, d = h.cmd(op(3, 0x14), b'', 'read local name')
        if st == 0:
            ORIG_NAME[:] = [bytes(d[1:249])]
        good &= ok('Write_Local_Name', h.cmd(op(3, 0x13), cfg.name.encode()[:20].ljust(248, bytes([0])), 'name')[0])
    if cfg.interlaced:
        good &= ok('Write_Inquiry_Scan_Type (interlaced)', h.cmd(op(3, 0x43), bytes([1]), 'inquiry scan type')[0])
    return good


def tune_scans(h):
    """Be an easy-to-find display: long inquiry/page scan windows. Returns the old settings."""
    old = {}
    for key, rd, wr in (('inq', 0x1D, 0x1E), ('page', 0x1B, 0x1C)):
        st, d = h.cmd(op(3, rd), b'', 'read %s scan activity' % key)
        old[key] = d[1:5] if st == 0 else None
        ok('Write_%s_Scan_Activity (320/160 ms)' % key.capitalize(),
           h.cmd(op(3, wr), struct.pack('<HH', 0x0200, 0x0100), 'write %s scan activity' % key)[0])
    return old


def restore_scans(h, old):
    for key, wr in (('inq', 0x1E), ('page', 0x1C)):
        if old and old.get(key):
            try:
                h.cmd(op(3, wr), old[key], 'restore %s scan activity' % key)
            except (TimeoutError, OSError):
                pass


def readback(h, cfg):
    expect = eir_3dd(cfg).rstrip(bytes([0]))
    st, d = h.cmd(op(3, 0x23), b'', 'read cod')
    cod = int.from_bytes(d[1:4], 'little') if st == 0 else -1
    st2, e = h.cmd(op(3, 0x51), b'', 'read eir')
    eir = bytes(e[2:2 + len(expect)]) if st2 == 0 else b''
    print('  readback: class of device 0x%06X (want 0x%06X), EIR %s%s'
          % (cod, cfg.cod, eir.hex(), '' if eir == expect else '  (want %s)' % expect.hex()))


def csb_start(h, cfg):
    good = True
    # The train timeout cannot be "none": the field is 2 .. 0x07BFA000 slots (about 22 h).  Use the longest the controller takes.
    for timeout in (getattr(cfg, 'train_timeout', 192000), 5760000, 192000):
        st = h.cmd(op(3, 0x78), struct.pack('<HHLB', cfg.train_interval, cfg.train_interval, timeout, cfg.service_data),
                   'sync train params')[0]
        if st == 0:
            break
    good &= ok('Write_Sync_Train_Parameters (timeout %.0f s)' % (timeout * 0.000625), st)
    if cfg.retx is not None:
        good &= ok('Write_Num_Broadcast_Retransmissions %d' % cfg.retx, h.cmd(op(3, 0x2A), bytes([cfg.retx]), 'retx')[0])
    if getattr(cfg, 'afh_assess', None) is not None:
        good &= ok('Write_AFH_Channel_Assessment_Mode %d' % cfg.afh_assess, h.cmd(op(3, 0x48), bytes([cfg.afh_assess]), 'afh mode')[0])
    if getattr(cfg, 'afh_all', False):
        good &= ok('Set_AFH_Host_Channel_Classification (all)', h.cmd(op(3, 0x3F), bytes([0xFF] * 9 + [0x7F]), 'afh classification')[0])
    good &= ok('Set_Reserved_LT_ADDR 1', h.cmd(op(3, 0x74), bytes([1]), 'reserved lt_addr')[0])
    if getattr(cfg, 'data_first', False):
        first = beacon_payload(0, 0, 600, 16000, 17300, 32700, 33366, 0)
        good &= ok('Set_CSB_Data (before enabling)', h.cmd(op(3, 0x76), struct.pack('<BBB', 1, getattr(cfg, 'fragment', 3), len(first)) + first, 'csb data')[0])
    st, data = h.cmd(op(1, 0x41), struct.pack('<BBBHHHH', 1, 1, 0, packet_mask(cfg), cfg.csb_interval,
                                              cfg.csb_interval, 0x7D00), 'set csb')
    good &= ok('Set_Connectionless_Slave_Broadcast', st)
    return good


def csb_stop(h):
    try:
        h.cmd(op(1, 0x41), struct.pack('<BBBHHHH', 0, 1, 0, 0x0008, 0x0080, 0x0080, 0x7D00), 'csb off')
        h.cmd(op(3, 0x75), bytes([1]), 'delete reserved lt_addr')
    except (TimeoutError, OSError):
        pass


def restore(h):
    csb_stop(h)
    try:
        h.cmd(op(3, 0x52), bytes([0]) + bytes(240), 'clear eir')
        h.cmd(op(3, 0x24), bytes([0, 0, 0]), 'cod')
        h.cmd(op(3, 0x43), bytes([0]), 'inquiry scan type standard')
        h.cmd(op(3, 0x1A), bytes([2]), 'scan enable (page scan only, as found)')
        if ORIG_NAME:
            h.cmd(op(3, 0x13), ORIG_NAME[0], 'restore local name')
    except (TimeoutError, OSError):
        pass


def read_clock(h):
    st, d = h.cmd(op(5, 0x07), bytes([0, 0, 0]), 'read clock')
    if st != 0:
        raise RuntimeError('Read_Clock failed 0x%02X' % st)
    return struct.unpack_from('<I', d, 3)[0] & 0x0FFFFFFF


def grid_reference(origin, clk_now, period_us):
    """Latest frame-sync instant at or before clk_now on the grid origin + n * period.
    Returns (clock tick, phase in us within that 312.5 us tick). Keeps the shutter phase
    stable between beacon updates."""
    ticks = period_us / 312.5
    n = int(((clk_now - origin) & 0x0FFFFFFF) // ticks)
    ref = origin + n * ticks
    clk = int(ref)
    return clk & 0x0FFFFFFF, int(round((ref - clk) * 312.5))


def pattern(rate_hz):
    """Frame = one left + one right image. Returns (period_us, frac256, l_open, l_close, r_open, r_close)."""
    period = 1e6 / rate_hz
    p_us = int(period)
    frac = int((period - p_us) * 256)
    half = period / 2
    guard = 600                                    # us of darkness around the switch
    return p_us, frac, int(guard), int(half - guard), int(half + guard), int(period - guard)


# Where does the glasses' timing run out?  30 Hz frame pair (33366.67 us) with the windows placed at different offsets.
TIMING_TESTS = {
    'h1': (33366, 170, 600, 7500, 8700, 15600),        # both windows before 16.4 ms
    'h2': (33366, 170, 600, 8000, 16500, 20500),       # right window opens after 16.4 ms, closes before 20.8 ms
    'h3': (33366, 170, 600, 8000, 21500, 30000),       # right window entirely after 20.8 ms
    'h4': (24000, 0, 600, 11000, 12100, 22500),        # 41.7 Hz period
    'c1': (16688, 248, 600, 7743, 8943, 16087),        # exactly what the live half-period beacon announced
    'c2': (16683, 0, 600, 7743, 8943, 16083),          # same shape, whole-microsecond period
    'c3': (20833, 170, 600, 9816, 11016, 20233),       # the 48 Hz pattern that works, but with a fractional period
    'q31': (31000, 0, 600, 14900, 16100, 30400),       # periods either side of 32768 us (2^15)
    'q327': (32700, 0, 600, 15750, 16950, 32100),
    'q330': (33000, 0, 600, 15900, 17100, 32400),
    'q340': (34000, 0, 600, 16400, 17600, 33400),
}


def preset(name):
    """Named shutter patterns for experiments -> (period_us, frac256, l_open, l_close, r_open, r_close)."""
    if name in TIMING_TESTS:
        return TIMING_TESTS[name]
    rate = {'sms': 29.97, 'smsrl': 29.97, 'half': 29.97, 'ctrl60': 59.94, 'r40': 40.0, 'r48': 48.0, 'clear': 59.94}[name]
    p_us, frac, lo, lc, ro, rc = pattern(rate)
    if name == 'clear':                       # 2D mode marker: both lenses open (spec: left open offset 0xFFFF)
        return p_us, frac, 0xFFFF, lc, ro, rc
    if name == 'smsrl':                       # right eye first, left second
        lo, lc, ro, rc = ro, rc, lo, lc
    if name == 'half':                        # both windows inside the first 16.7 ms of a 33.4 ms period
        lo, lc, ro, rc = 600, 6000, 8000, 13500
    return p_us, frac, lo, lc, ro, rc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['check', 'assoc', 'beacon'])
    ap.add_argument('--dev', default='0', help='hciN number (default 0) or a serial port with an ESP32 HCI bridge, e.g. COM8')
    ap.add_argument('--seconds', type=float, default=60.0)
    ap.add_argument('--rate', type=float, default=59.94, help='frame (left+right) rate in Hz')
    ap.add_argument('--train', choices=['always', 'onpage'], default='always')
    ap.add_argument('--cod', type=lambda v: int(v, 0), default=0x00043C)
    ap.add_argument('--eir-flags', dest='eir_flags', type=lambda v: int(v, 0), default=0x01)
    ap.add_argument('--tx-power', dest='tx_power', type=int, default=4)
    ap.add_argument('--path-loss', dest='path_loss', type=int, default=100)
    ap.add_argument('--service-data', dest='service_data', type=lambda v: int(v, 0), default=0)
    ap.add_argument('--train-interval', dest='train_interval', type=lambda v: int(v, 0), default=0x0080)
    ap.add_argument('--csb-interval', dest='csb_interval', type=lambda v: int(v, 0), default=0x0080)
    ap.add_argument('--packet', choices=['DM1', 'DH1'], default='DM1')
    ap.add_argument('--retx', type=int, default=None)
    ap.add_argument('--name', default='')
    ap.add_argument('--interlaced', action='store_true')
    ap.add_argument('--afh-all', dest='afh_all', action='store_true', help='mark all 79 channels usable (host AFH classification)')
    ap.add_argument('--afh-assess', dest='afh_assess', type=int, default=None, help='AFH channel assessment mode 0/1')
    ap.add_argument('--data-first', dest='data_first', action='store_true', help='send the first beacon data before enabling the broadcast')
    ap.add_argument('--fragment', type=lambda v: int(v, 0), default=3, help='Set_CSB_Data fragment flag (3 = no fragmentation)')
    ap.add_argument('--data-once', dest='data_once', action='store_true', help='set the beacon data once instead of every 80 ms')
    ap.add_argument('--pad', type=int, default=0, help='pad or cut the beacon payload to this many bytes (experiment)')
    ap.add_argument('--phases', default='', help='beacon mode: comma list of presets (sms,smsrl,half,ctrl60,r40,r48), each shown for --phase-seconds')
    ap.add_argument('--phase-seconds', dest='phase_seconds', type=float, default=35.0)
    ap.add_argument('--phases-file', dest='phases_file', default=None, help='beacon mode: re-read the --phases list from this file whenever it changes (no restart, glasses stay synced)')
    ap.add_argument('--raw-log', dest='raw_log', default=None, help='save all bytes received from an ESP32 bridge')
    cfg = ap.parse_args()
    global RAW_LOG
    RAW_LOG = cfg.raw_log

    h = open_hci(cfg.dev)
    old_scans = None
    try:
        if cfg.mode == 'check':
            print('configuring as 3D display ...')
            good = setup(h, cfg)
            good &= ok('Write_Scan_Enable (inquiry+page)', h.cmd(op(3, 0x1A), bytes([3]), 'scan')[0])
            good &= csb_start(h, cfg)
            p_us, frac, lo, lc, ro, rc = pattern(cfg.rate)
            clk = read_clock(h)
            print('  native clock 0x%07X' % clk)
            data = beacon_payload(clk, 0, lo, lc, ro, rc, p_us, frac)
            good &= ok('Set_CSB_Data (17 bytes)', h.cmd(op(3, 0x76), struct.pack('<BBB', 1, getattr(cfg, 'fragment', 3), len(data)) + data, 'csb data')[0])
            st, _ = h.cmd(op(1, 0x43), b'', 'start sync train')
            good &= ok('Start_Synchronization_Train', st)
            time.sleep(1.0)
            print('restoring ...')
            restore(h)
            print('RESULT:', 'all commands accepted' if good else 'SOME COMMANDS FAILED')
            return 0 if good else 1

        print('configuring as 3D display ...')
        setup(h, cfg)
        old_scans = tune_scans(h)
        ok('Write_Scan_Enable (inquiry+page)', h.cmd(op(3, 0x1A), bytes([3]), 'scan')[0])
        readback(h, cfg)
        t_start = time.monotonic()
        end = t_start + cfg.seconds
        counts = {}

        def log_event(code, data):
            counts[code] = counts.get(code, 0) + 1
            if code != 0x13:
                print('%6.1f s  %s' % (time.monotonic() - t_start, describe(code, data)), flush=True)

        if cfg.mode == 'assoc':
            print('discoverable as a 3D display for %.0f s. Put the glasses into association mode now'
                  ' (hold the button until the LED blinks) and keep them near the MiSTer.' % cfg.seconds)
            while time.monotonic() < end:
                ev = h.pump(0.5)
                if ev:
                    log_event(*ev)
        else:
            csb_start(h, cfg)
            phases = []
            for item in [x for x in cfg.phases.split(',') if x]:
                nm, _, sec = item.partition(':')
                phases.append((nm, float(sec) if sec else cfg.phase_seconds))
            cycle = sum(sec for _, sec in phases)
            cur_phase = None
            file_mtime = None
            next_file_check = 0.0
            if phases:
                p_us, frac, lo, lc, ro, rc = preset(phases[0][0])
            else:
                p_us, frac, lo, lc, ro, rc = pattern(cfg.rate)
                print('beacon: frame %.2f Hz, period %d us, left open %d..%d us, right open %d..%d us'
                      % (cfg.rate, p_us, lo, lc, ro, rc))
            if cfg.train == 'always':
                st, _ = h.cmd(op(1, 0x43), b'', 'start sync train')
                ok('Start_Synchronization_Train', st)
            else:
                print('  sync train will start when the glasses page us (Slave Page Response Timeout)')
            origin = read_clock(h)
            period_exact = p_us + frac / 256.0
            next_update = 0
            t_beacon = time.monotonic()
            fails = 0
            seen_reboots = getattr(h, 'reboots', 0)
            while time.monotonic() < end:
                try:
                    now = time.monotonic()
                    if cfg.phases_file and now >= next_file_check:
                        next_file_check = now + 0.3
                        try:
                            mt = os.stat(cfg.phases_file).st_mtime
                            if mt != file_mtime:
                                file_mtime = mt
                                items = [x for x in open(cfg.phases_file).read().strip().split(',') if x]
                                new_phases = []
                                for item in items:
                                    nm, _, sec = item.strip().partition(':')
                                    preset(nm)                      # unknown name -> KeyError -> list ignored
                                    new_phases.append((nm, float(sec) if sec else cfg.phase_seconds))
                                if new_phases:
                                    phases = new_phases
                                    cycle = sum(sec for _, sec in phases)
                                    t_beacon = now
                                    cur_phase = None
                                    print('%6.1f s  new phase list: %s' % (now - t_start, ','.join('%s:%g' % ph for ph in phases)), flush=True)
                        except (OSError, ValueError, KeyError):
                            pass
                    if phases:
                        pos = (now - t_beacon) % cycle
                        idx = 0
                        while pos >= phases[idx][1]:
                            pos -= phases[idx][1]
                            idx += 1
                        if idx != cur_phase:
                            cur_phase = idx
                            p_us, frac, lo, lc, ro, rc = preset(phases[idx][0])
                            period_exact = p_us + frac / 256.0
                            origin = read_clock(h)
                            print('%6.1f s  PHASE %d: %s  period %d us (%.2f Hz), left %d..%d us, right %d..%d us'
                                  % (now - t_start, idx + 1, phases[idx][0], p_us, 1e6 / period_exact, lo, lc, ro, rc), flush=True)
                    if now >= next_update and not (cfg.data_once and next_update > 0):
                        clk, phase = grid_reference(origin, read_clock(h), period_exact)
                        data = beacon_payload(clk, phase, lo, lc, ro, rc, p_us, frac)
                        if cfg.pad:
                            data = data[:cfg.pad].ljust(cfg.pad, bytes([0]))
                        h.cmd(op(3, 0x76), struct.pack('<BBB', 1, getattr(cfg, 'fragment', 3), len(data)) + data, 'csb data')
                        next_update = now + 0.08
                    ev = h.pump(0.02)
                    if ev:
                        code, data = ev
                        log_event(code, data)
                        if code == EV_SYNC_TRAIN_COMPLETE:
                            if cfg.train == 'always':
                                h.cmd(op(1, 0x43), b'', 'start sync train')
                        elif code == EV_PAGE_TIMEOUT and cfg.train == 'onpage':
                            st, _ = h.cmd(op(1, 0x43), b'', 'start sync train')
                            print('          -> started synchronization train (status 0x%02X)' % st, flush=True)
                except TimeoutError as err:
                    fails += 1
                    print('%6.1f s  !! controller not responding (%s)' % (time.monotonic() - t_start, err), flush=True)
                    if fails > 6:
                        raise
                    if getattr(h, 'reboots', 0) > seen_reboots:
                        seen_reboots = h.reboots
                        print('          -> controller restarted, configuring it again', flush=True)
                        setup(h, cfg)
                        tune_scans(h)
                        h.cmd(op(3, 0x1A), bytes([3]), 'scan')
                        csb_start(h, cfg)
                        if cfg.train == 'always':
                            h.cmd(op(1, 0x43), b'', 'start sync train')
                        origin = read_clock(h)
                    else:
                        time.sleep(0.3)
        readback(h, cfg)
        print('event counts:', {EV_NAMES.get(k, hex(k)): v for k, v in counts.items() if k != 0x13} or 'none')
        return 0
    finally:
        if hasattr(h, 'hard_reset'):
            print('resetting the ESP32 ...')
            h.hard_reset()
        else:
            print('restoring controller ...')
            restore_scans(h, old_scans)
            restore(h)


if __name__ == '__main__':
    sys.exit(main())
