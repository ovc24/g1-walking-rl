#!/usr/bin/env python3
"""Virtual Xbox-style gamepad driven from the keyboard, for the sim2sim without a real pad.

unitree_mujoco needs a gamepad (/dev/input/js0) and g1_ctrl changes state only with
gamepad combos. This script creates a virtual pad through uinput with the same button and
axis numbering as a real Xbox pad (A=0, B=1, LT=axis 2, RT=axis 5, d-pad=axes 6/7), so the
simulator and g1_ctrl stay exactly as they are (the same g1_ctrl as on the real robot).

    sudo apt install python3-evdev        # once
    sudo python3 keyboard_pad.py          # BEFORE starting the simulator; keep this
                                          # terminal focused to drive the robot

Keys (in this terminal):
    1        stand up       (LT + up)
    2        start policy   (RT + A)
    0        passive        (LT + B)     <- emergency stop, also works from any state
    w / s    forward / back     (+-0.1 m/s per press, -0.5..1.0)
    a / d    left / right       (+-0.1 m/s per press, -0.5..0.5)
    q / e    turn left / right  (+-0.1 rad/s per press, -1.0..1.0)
    space    stop (all speeds to 0)
    x        quit (speeds to 0, pad removed)

The speed limits are those of deploy.yaml (g1_ctrl clamps the sticks to them). Below
0.1 in total g1_ctrl treats the command as "stand" (gait clock off).
"""
import glob
import os
import select
import sys
import termios
import time
import tty

try:
    from evdev import AbsInfo, UInput, ecodes as e
except ImportError:                                   # pragma: no cover
    sys.exit("python-evdev is missing: sudo apt install python3-evdev")

STEP = 0.1
LIMITS = {"vx": (-0.5, 1.0), "vy": (-0.5, 0.5), "wz": (-1.0, 1.0)}
STICK_MAX = 32767
TRIGGER_MAX = 255
LEAD_S = 0.15     # trigger held this long before the button (combos are "LT + B.on_pressed")
HOLD_S = 0.30     # button held this long


def make_pad():
    """uinput device shaped like an Xbox 360 pad (xpad driver): joydev numbers the axes
    and buttons in code order, which gives the layout unitree_mujoco's XBoxJoystick reads."""
    stick = AbsInfo(value=0, min=-32768, max=32767, fuzz=0, flat=0, resolution=0)
    trigger = AbsInfo(value=0, min=0, max=TRIGGER_MAX, fuzz=0, flat=0, resolution=0)
    hat = AbsInfo(value=0, min=-1, max=1, fuzz=0, flat=0, resolution=0)
    caps = {
        e.EV_KEY: [e.BTN_A, e.BTN_B, e.BTN_X, e.BTN_Y, e.BTN_TL, e.BTN_TR,
                   e.BTN_SELECT, e.BTN_START, e.BTN_MODE, e.BTN_THUMBL, e.BTN_THUMBR],
        e.EV_ABS: [(e.ABS_X, stick), (e.ABS_Y, stick), (e.ABS_Z, trigger),
                   (e.ABS_RX, stick), (e.ABS_RY, stick), (e.ABS_RZ, trigger),
                   (e.ABS_HAT0X, hat), (e.ABS_HAT0Y, hat)],
    }
    return UInput(caps, name="Keyboard gamepad (sim2sim)", vendor=0x045e, product=0x028e,
                  version=0x110, bustype=e.BUS_USB)


def find_js(ui, timeout=2.0):
    """The /dev/input/jsN that joydev made for our device (None if not found)."""
    try:
        ev = os.path.basename(ui.device.path)
    except Exception:                                 # noqa: BLE001
        return None
    end = time.time() + timeout
    while time.time() < end:
        found = glob.glob("/sys/class/input/%s/device/js*" % ev)
        if found:
            return "/dev/input/" + os.path.basename(found[0])
        time.sleep(0.1)
    return None


class Pad:
    """Speeds and button combos -> uinput events. g1_ctrl reads: vx = ly, vy = -lx,
    turn = -rx, and the simulator: ly = -axis1, lx = axis0, rx = axis3 (all / 32768)."""

    def __init__(self, ui, sleep=time.sleep):
        self.ui, self.sleep = ui, sleep
        self.vx = self.vy = self.wz = 0.0
        self.last = "passive (start)"

    def _sticks(self):
        w = self.ui.write
        w(e.EV_ABS, e.ABS_Y, int(round(-self.vx * STICK_MAX)))
        w(e.EV_ABS, e.ABS_X, int(round(-self.vy * STICK_MAX)))
        w(e.EV_ABS, e.ABS_RX, int(round(-self.wz * STICK_MAX)))
        self.ui.syn()

    def _combo(self, trigger, btn_type, btn_code, btn_value):
        """Hold the trigger, then press the button while it is held, then release both."""
        w = self.ui.write
        w(e.EV_ABS, trigger, TRIGGER_MAX)
        self.ui.syn()
        self.sleep(LEAD_S)
        w(btn_type, btn_code, btn_value)
        self.ui.syn()
        self.sleep(HOLD_S)
        w(btn_type, btn_code, 0)
        self.ui.syn()
        self.sleep(0.05)
        w(e.EV_ABS, trigger, 0)
        self.ui.syn()

    def _bump(self, name, delta):
        lo, hi = LIMITS[name]
        value = round(getattr(self, name) + delta, 2)
        setattr(self, name, min(hi, max(lo, value)))
        self._sticks()

    def stop(self):
        self.vx = self.vy = self.wz = 0.0
        self._sticks()

    def key(self, ch):
        """Handle one key. Returns False to quit."""
        ch = ch.lower()
        if ch == "1":
            self.stop()
            self._combo(e.ABS_Z, e.EV_ABS, e.ABS_HAT0Y, -1)      # LT + d-pad up
            self.last = "stand up (LT + up)"
        elif ch == "2":
            self.stop()
            self._combo(e.ABS_RZ, e.EV_KEY, e.BTN_A, 1)          # RT + A
            self.last = "policy (RT + A)"
        elif ch == "0":
            self.stop()
            self._combo(e.ABS_Z, e.EV_KEY, e.BTN_B, 1)           # LT + B
            self.last = "PASSIVE (LT + B)"
        elif ch in ("w", "s"):
            self._bump("vx", STEP if ch == "w" else -STEP)
            self.last = "speed"
        elif ch in ("a", "d"):
            self._bump("vy", STEP if ch == "a" else -STEP)
            self.last = "speed"
        elif ch in ("q", "e"):
            self._bump("wz", STEP if ch == "q" else -STEP)
            self.last = "speed"
        elif ch == " ":
            self.stop()
            self.last = "stop"
        elif ch == "x":
            self.stop()
            return False
        return True

    def status(self):
        return ("vx %+.1f m/s  vy %+.1f m/s  turn %+.1f rad/s  | last: %s"
                % (self.vx, self.vy, self.wz, self.last))


def main():
    try:
        ui = make_pad()
    except PermissionError:
        sys.exit("No access to /dev/uinput: run with sudo (sudo python3 keyboard_pad.py)")
    except OSError as err:
        sys.exit("Could not create the virtual pad (%s). Try: sudo modprobe uinput" % err)
    pad = Pad(ui)
    pad.stop()
    js = find_js(ui)
    print(__doc__.split("Keys (in this terminal):")[1].split("The speed limits")[0].rstrip())
    if js:
        print("\nVirtual pad ready as %s (set joystick_device in simulate/config.yaml if it"
              " is not js0)." % js)
        if os.stat(js).st_mode & 0o004 == 0:
            print("If the simulator says 'Joystick open failed': sudo chmod a+r %s" % js)
    else:
        print("\nVirtual pad created, but no /dev/input/js* appeared: sudo modprobe joydev,"
              " then start this script again.")
    print("Now start the simulator, then g1_ctrl. Keep THIS terminal focused.\n")

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        sys.stdout.write("\r" + pad.status() + "    ")
        sys.stdout.flush()
        while True:
            ready, _, _ = select.select([sys.stdin], [], [], 0.2)
            if not ready:
                continue
            ch = sys.stdin.read(1)
            if not ch:
                break
            if not pad.key(ch):
                break
            sys.stdout.write("\r" + pad.status() + "    ")
            sys.stdout.flush()
    except KeyboardInterrupt:
        pass
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        try:
            pad.stop()
        finally:
            ui.close()
        print("\nVirtual pad removed.")


if __name__ == "__main__":
    main()
