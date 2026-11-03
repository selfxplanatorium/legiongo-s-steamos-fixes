#!/usr/bin/env python3
"""Legion Go S touchpad diagnostic.

Reads the controller's raw HID reports for a fixed time and reports, per
finger stroke, what the two touchpad data paths carry:

  * IF2 (hid-multitouch digitizer, report 0x31): absolute x/y, tip switch,
    scan time, button bits.
  * IF6 (gamepad report): byte 8 bit 0 = touching, byte 9 bit 0 = tap/click,
    bytes 10/11 = signed 8-bit relative dx/dy.

Run as root while touching the pad:  sudo python3 -I touchpad-diag.py [seconds]
Reading hidraw nodes does not interfere with InputPlumber.
"""
import glob
import os
import select
import sys
import time
from collections import Counter

DURATION = float(sys.argv[1]) if len(sys.argv) > 1 else 30.0


def find_nodes():
    nodes = {}
    for h in glob.glob("/sys/class/hidraw/hidraw*"):
        try:
            uevent = open(os.path.join(h, "device/uevent")).read().upper()
        except OSError:
            continue
        if "1A86:0000E31" not in uevent and "1A86:E31" not in uevent:
            continue
        iface = os.path.basename(os.path.dirname(os.path.realpath(os.path.join(h, "device"))))
        # iface looks like "1-1:1.2"
        if iface.endswith(":1.2"):
            nodes["pad"] = "/dev/" + os.path.basename(h)
        elif iface.endswith(":1.6"):
            nodes["gamepad"] = "/dev/" + os.path.basename(h)
    return nodes


def s8(b):
    return b - 256 if b > 127 else b


def main():
    nodes = find_nodes()
    if "gamepad" not in nodes:
        sys.exit("Legion Go S gamepad interface (IF6) not found")
    fds = {os.open(n, os.O_RDONLY | os.O_NONBLOCK): k for k, n in nodes.items()}
    print(f"capturing {DURATION:.0f} s from {nodes} - touch, swipe and click the pad now", flush=True)

    pad_frames = Counter()
    pad_x, pad_y, pad_scan = set(), set(), set()
    pad_tip = pad_btn = 0
    strokes, cur, clicks, last_tap = [], None, 0, 0
    t0 = time.time()
    while time.time() - t0 < DURATION:
        ready, _, _ = select.select(list(fds), [], [], 0.5)
        for fd in ready:
            try:
                d = os.read(fd, 64)
            except OSError:
                continue
            if fds[fd] == "pad":
                if d and d[0] == 0x31 and len(d) >= 10:
                    pad_frames[d[:10].hex(" ")] += 1
                    pad_x.add(d[2] | d[3] << 8)
                    pad_y.add(d[4] | d[5] << 8)
                    pad_scan.add(d[6] | d[7] << 8)
                    pad_tip += (d[1] >> 1) & 1
                    pad_btn += d[9] & 7
                continue
            if len(d) < 12:
                continue
            touching, tap = d[8] & 1, d[9] & 1
            if tap and not last_tap:
                clicks += 1
            last_tap = tap
            if touching and cur is None:
                cur = dict(t=time.time() - t0, n=0, dx=0, dy=0)
            if cur is not None:
                cur["n"] += 1
                cur["dx"] += s8(d[10])
                cur["dy"] += s8(d[11])
                if not touching:
                    strokes.append(cur)
                    cur = None

    print("\nIF2 digitizer (report 0x31):")
    print(f"  reports={sum(pad_frames.values())} distinct={len(pad_frames)} "
          f"x_values={len(pad_x)} y_values={len(pad_y)} scan_times={len(pad_scan)} "
          f"tip_reports={pad_tip} button_reports={pad_btn}")
    for frame, n in pad_frames.most_common(3):
        print(f"  {n:6d}  {frame}")
    print("\nIF6 gamepad report touch fields:")
    print(f"  strokes={len(strokes)} clicks={clicks}")
    for s in strokes:
        if s["n"] > 5:
            print(f"  t={s['t']:5.1f}s reports={s['n']:4d} net dx={s['dx']:5d} dy={s['dy']:5d}")

    frozen = len(pad_x) <= 1 and len(pad_y) <= 1 and pad_tip == 0
    moving = any(abs(s["dx"]) + abs(s["dy"]) > 20 for s in strokes)
    print("\nRESULT:")
    if frozen and moving:
        print("  IF2 digitizer frozen, gamepad report carries live motion -> needs the patched InputPlumber")
    elif moving:
        print("  gamepad report carries motion and IF2 also changes -> IF2 path may work on this firmware")
    elif not strokes:
        print("  no touch seen in the gamepad report (did you touch the pad? relative mode?)")
    else:
        print("  touches seen without motion")


if __name__ == "__main__":
    main()
