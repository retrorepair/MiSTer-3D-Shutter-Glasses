# MicroPython for RP2040 (Raspberry Pi Pico or similar): USB IR emitter for active-shutter
# 3-D glasses, driven by the MiSTer daemon (mister_glasses_daemon.py).
# UNTESTED on real glasses - check the LED with a phone camera, then see README.md.
#
# The MiSTer sends one byte per event over USB serial:
#   'L' left lens open now   'R' right lens open now   '0' no 3-D game running
#
# Wiring: GP15 -> 1 kOhm -> base of an NPN transistor (2N2222 / BC337),
#         emitter -> GND, collector -> IR LED cathode, IR LED anode -> 47-100 Ohm -> VBUS (5 V).
#         (GP15 -> 150 Ohm -> IR LED -> GND also works for a few metres less range.)
#
# Sony 3D sync IR protocol (TDG-BR100 era, from Woods & Helliwell, SPIE 8288 fig. 12).
# A token is  H20 L20 H20 L20 H20 L<gap> H20 L20 H20  microseconds, the gap picks the command:
#   close right eye 220, open left eye 140, close left eye 380, open right eye 300.

import sys
import select
import time
import rp2
from machine import Pin

IR_PIN = 15

# ---------------------------------------------------------------------------
# PIO: plays (level, duration) segments from the TX FIFO at a 1 MHz state machine clock.
# FIFO word: bit0 = output level, bits 31..1 = duration in us minus 4 (the program
# spends 4 cycles of fixed overhead per segment).
# ---------------------------------------------------------------------------
@rp2.asm_pio(out_init=rp2.PIO.OUT_LOW, out_shiftdir=rp2.PIO.SHIFT_RIGHT, fifo_join=rp2.PIO.JOIN_TX)
def play():
    pull(block)
    out(pins, 1)
    out(x, 31)
    label("wait")
    jmp(x_dec, "wait")


sm = rp2.StateMachine(0, play, freq=1_000_000, out_base=Pin(IR_PIN))
sm.active(1)

# ---------------------------------------------------------------------------
# Sony protocol
# ---------------------------------------------------------------------------
PULSE = 20
GAP = {'close_r': 220, 'open_l': 140, 'close_l': 380, 'open_r': 300}
TOKEN_SPACE = 100          # idle time after each token


def seg(level, us):
    return ((us - 4) << 1) | level


def token(gap_us):
    return [seg(1, PULSE), seg(0, PULSE), seg(1, PULSE), seg(0, PULSE), seg(1, PULSE),
            seg(0, gap_us),
            seg(1, PULSE), seg(0, PULSE), seg(1, PULSE), seg(0, TOKEN_SPACE)]


# Close the other eye first, then open this one. The last word has level 0, so the LED
# is off whenever the state machine is waiting for the next sequence.
SEQ = {
    'L': token(GAP['close_r']) + token(GAP['open_l']),
    'R': token(GAP['close_l']) + token(GAP['open_r']),
}


def send(eye):
    for w in SEQ[eye]:
        sm.put(w)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
KEEPALIVE_MS = 40          # resend the state if the eye does not change
WATCHDOG_MS = 400          # no byte from the MiSTer for this long -> stop emitting

try:
    led = Pin("LED", Pin.OUT)
except Exception:
    led = Pin(25, Pin.OUT)

poll = select.poll()
poll.register(sys.stdin, select.POLLIN)

state = '0'
last_rx = time.ticks_ms()
last_tx = last_rx

while True:
    if poll.poll(2):
        ch = sys.stdin.read(1)
        now = time.ticks_ms()
        if ch in ('L', 'R'):
            state = ch
            last_rx = now
            send(ch)
            last_tx = time.ticks_ms()
            led.toggle()
        elif ch == '0':
            state = '0'
            led.off()
    now = time.ticks_ms()
    if state != '0':
        if time.ticks_diff(now, last_rx) > WATCHDOG_MS:
            state = '0'
            led.off()
        elif time.ticks_diff(now, last_tx) > KEEPALIVE_MS:
            send(state)
            last_tx = time.ticks_ms()
