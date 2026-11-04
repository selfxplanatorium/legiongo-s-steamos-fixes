# How each problem was found

This page records the evidence behind each fix, including the approaches that
didn't work. The exact interface details are in the [reference](reference.md).

All measurements come from one Legion Go S 83L3 in November 2026:

- SteamOS 3.9.5 with kernel `7.2.7-valve2-2-neptune`
- InputPlumber 0.78.0 from the SteamOS image, then 0.83.1
- `steamos-manager` 26.4.1
- Controller firmware 0.0.4.3, touchpad SIPO firmware v12

## How input flows on this device

InputPlumber reads three of the controller's interfaces through hidraw:

- IF2, the touchpad
- IF5, the IMU
- IF6, the gamepad

It hides the original devices from other programs and combines them into one
composite device. The composite device then presents a virtual controller to
Steam. Each fix below targets one step of that chain.

## Gyro: values off by a factor of about 160

The virtual controller's reports showed the accelerometer at about ±100 units
with the device lying still. Steam expects about 16384 units per g, so it was
seeing roughly 0.006 g. InputPlumber 0.78.0 passed the raw IMU values to the
virtual controller without scaling them.

InputPlumber 0.83.1 fixes the scaling. With 0.83.1 installed, the
accelerometer Z axis read between −16604 and −16296 at rest (about −1 g), and
gyro noise at rest stayed between 5 and 20 units (standard deviation). The
Legion Go S device file and default profile are byte-identical in both
versions, so the change comes from the driver code.

## Steam target: the default virtual controller is ignored

SteamOS starts InputPlumber with the `deck-uhid` target, a virtual controller
with USB ID `28de:12ff`. The Steam client logged
`Unrecognized controller using V1 HID protocol` for it and never started the
HID handshake that it performs with real Steam controllers. Without that
handshake, Steam doesn't use gyro, trackpads or rumble.

The `deck` target creates a virtual USB device, `28de:1205`, that appears as
"Valve Software Steam Controller". Steam logged
`Controller uses V1 HID protocol`, reported `HWID: 46` and loaded
`configset_controller_neptune.vdf`, its Steam Deck configuration.

`steamos-manager` decides which target InputPlumber uses, and its device file
only allows `deck-uhid`, `keyboard` and `mouse`. Writing `deck` there is a
parse error that makes the daemon fail on every start. For that reason,
`deck-target.sh` sets the target over D-Bus after `steamos-manager` has done
its part. Adding `keyboard` and `mouse` also gives Desktop Mode a pointer,
which the stock configuration lacks.

## Rumble: vibration is off in the controller

Rumble packets reached the controller on both paths: the xpad path
(`00 08 00 ff ff 00 00 00` on endpoint `0x02`) and the vendor path
(`04 00 08 00 ff ff 00 00 00` as a SET_REPORT on IF6). The controller
acknowledged both, and the motors stayed still.

The controller's MCU has a vibration setting that ships turned off. On
Windows, Lenovo's Legion Space app turns it on, and no Linux component did.
Writing `08 01 01` to the MCU control interface (IF3) turns it on. The
command came from probing the MCU's command set (see the
[MCU command map](reference.md#mcu-command-map)). HHD, another handheld
input daemon, uses neighboring commands of the same family in its Legion Go S
reset sequence.

The internal microphone confirmed the result. This table lists the root mean
square of the first difference of the recording while rumble was requested:

| Condition | Level |
|-----------|-------|
| Before the enable command | 0.38 |
| After `08 01 01` | 3.33 |
| Repeated later | 3.85 |
| After reapplying through udev | 2.98 |
| After restarting InputPlumber | 3.35 |
| After a USB power cycle | 3.11 |
| After reloading the driver | 3.68 |

Each `08 01 01` also runs the motors for about two seconds on its own. An
early version of the fix resent the command every 60 seconds and caused
random buzzing, so `configure.sh` sends it once per controller connection.
An early resume hook forced it again on every wake and buzzed each time. On
the test unit the controller keeps its device instance through s2idle
suspend, so the resume hook now skips it, and udev covers a controller that
does reconnect.

## Touchpad: the real data is in the gamepad report

With the touchpad in absolute mode, IF2 sent its touchpad report (`0x31`)
only while a finger was on the touchpad, so touch detection itself worked.
Every report carried the same values, though:

```text
31 01 90 01 00 01 08 00 01 00
31 01 90 01 00 01 08 00 00 00
```

Decoded with the touchpad's report descriptor, X sits at its maximum (400),
Y at 256, and the scan time at 8 without ever advancing. The tip switch and
button bits stay 0. InputPlumber's touchpad driver only reacts when X, Y or
the tip switch change, so it never sent anything to Steam.

While a finger moved across the touchpad, the IF6 gamepad report changed
continuously. It arrives about 125 times per second. Byte 8 showed the finger
on the touchpad, byte 9 showed clicks, and bytes 10 and 11 carried small
signed values that changed sign when the swipe reversed direction. Full-width swipes added up to 330 to 460
units. InputPlumber 0.83.1 already names these fields in its gamepad report
definition (`rpad_touching`, `rpad_tap`, `touch_x`, `touch_y`, marked
"Deprecated"), but its driver never reads them.

The patch in `inputplumber/` turns those fields into right trackpad events.
Each touch starts at the center of the touchpad, the movement values shift the
position within the 0 to 400 range, and a click produces a trackpad press.
With the patched build, touchpad movement and clicks worked in Steam.

### What didn't help

These changes left the touchpad report frozen:

- Switching `touchpad/linux_mode` and `touchpad/windows_mode` between
  `absolute` and `relative`. In relative mode, neither IF2 nor IF6 reports any
  touch data.
- Setting `os_mode` to `windows`.
- Sending the MCU touchpad enable command (`04 08 01`) again.
- Unbinding and rebinding the USB device.
- Reloading the `hid_lenovo_go_s` driver.
- A controller factory reset (Quick Access + RB + Menu for four seconds).
- Reinstalling controller firmware 0.0.4.3 with fwupd. fwupd lists the
  touchpad (SIPO, version 12) as a child device but can't update it.

Upstream issue
[ShadowBlip/InputPlumber#604](https://github.com/ShadowBlip/InputPlumber/issues/604)
describes related SIPO touchpad problems with mode switching and driver
binding.

## Hung MCU

Repeated USB resets during testing left the MCU unresponsive. The kernel
logged `Failed to retrieve MCU ID: -16` (`EBUSY`), the IF3 sysfs settings
disappeared, and button combinations did nothing. Reloading
`hid_lenovo_go_s` recovered it every time. The commands are in
[troubleshooting](troubleshooting.md#the-controller-stops-responding).

## Persistence on SteamOS

`/etc` is an overlay whose writable layer lives on `/var`, and `/opt` is
stored under `/home/.steamos/offload/opt`. Both survive SteamOS image updates,
and a factory reset clears both. The installer uses only these two locations,
so the read-only root filesystem stays enabled.
