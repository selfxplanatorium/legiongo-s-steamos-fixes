# Reference

Exact details of what this repository installs and of the controller
interfaces it uses. The [findings](findings.md) explain how these were worked
out.

## Installed files

| Path | Installed from | Description |
|------|----------------|-------------|
| `/opt/inputplumber-legion-go-s/inputplumber` | `dist/inputplumber` | Patched InputPlumber. The installer keeps the previous copy as `inputplumber.prev` |
| `/etc/systemd/system/inputplumber.service.d/10-legion-go-s.conf` | `files/etc/...` | Replaces `ExecStart` of `inputplumber.service` with the patched binary |
| `/etc/legion-go-s/configure.sh` | `files/etc/...` | Controller setup, see [configure.sh](#configuresh) |
| `/etc/udev/rules.d/99-legion-go-s.rules` | `files/etc/...` | Runs `configure.sh` when the MCU control interface (IF3) of `1a86:e310` or `1a86:e311` appears |
| `/etc/systemd/system/legion-go-s-resume.service` | `files/etc/...` | Runs `configure.sh` after suspend, hibernate, hybrid sleep and suspend-then-hibernate. It does nothing when the controller kept its device instance, so waking doesn't make the motors buzz |
| `/etc/legion-go-s/deck-target.sh` | `files/etc/...` | Target loop, see [deck-target.sh](#deck-targetsh) |
| `/etc/systemd/system/legion-go-s-deck-target.service` | `files/etc/...` | Runs `deck-target.sh` and restarts it if it exits |
| `/etc/legion-go-s/check-inputplumber.sh` | `files/etc/...` | Version check, see [check-inputplumber.sh](#check-inputplumbersh) |
| `/etc/systemd/system/legion-go-s-inputplumber-check.service` | `files/etc/...` | Runs the version check once per boot |

All scripts log to the journal with the tag `legion-go-s`. Read the messages
with `journalctl -t legion-go-s`.

## configure.sh

`configure.sh [--force]`

Waits 1.5 seconds for the controller's MCU to finish starting, then:

1. Sends `08 01 01` to IF3, which turns on vibration.
2. Sends `04 08 01` to IF3, which turns on the touchpad.
3. Writes `absolute` to `touchpad/linux_mode` and `touchpad/windows_mode`, and
   `true` to `touchpad/enabled`, in the IF3 sysfs directory.

The script runs once for each HID device instance, such as
`0003:1A86:E310.0056`. It records finished instances in `/run/legion-go-s/`
and serializes runs with a lock file in that directory. When the controller
reconnects, the kernel gives it a new instance name, so the setup runs again.
`--force` skips the instance check.

The script always exits with status 0, so it never makes a udev event fail.
Errors go to the journal.

## deck-target.sh

Every two seconds, reads the `TargetDevices` property of
`/org/shadowblip/InputPlumber/CompositeDevice0` on the system bus. If no
target has the device type `deck`, it calls `SetTargetDevices` with
`deck`, `keyboard` and `mouse`. It logs each change.

## check-inputplumber.sh

Compares the output of `inputplumber --version` for
`/opt/inputplumber-legion-go-s/inputplumber` and `/usr/bin/inputplumber`. It
logs a warning when the SteamOS version is equal to or newer than the patched
version, and an informational message otherwise.

## Patched InputPlumber settings

The patch reads two environment variables when InputPlumber starts. Set them
in a drop-in for `inputplumber.service`, as shown in
[troubleshooting](troubleshooting.md#the-touchpad-is-too-slow-or-too-fast).

| Variable | Default | Effect |
|----------|---------|--------|
| `INPUTPLUMBER_LEGION_GO_S_GAMEPAD_TOUCHPAD` | enabled | `0` turns off the gamepad-report touchpad path. Any other value, or no value, leaves it on |
| `INPUTPLUMBER_LEGION_GO_S_GAMEPAD_TOUCHPAD_GAIN` | `1.0` | Multiplier for the touchpad movement. Must be a positive number. Invalid values fall back to `1.0` |

## Controller interfaces

The controller is one USB device with seven interfaces. Its USB ID is
`1a86:e310` in XInput mode and `1a86:e311` in DInput mode.

| Interface | Content | Kernel driver | Used by |
|-----------|---------|---------------|---------|
| IF0 | Boot keyboard | `hid-lenovo-go-s` | |
| IF1 | Vendor class `0xff/0x5d/0x01` | `xpad` | |
| IF2 | Mouse and touchpad digitizer (report `0x31`) | `hid-multitouch` | InputPlumber touchpad source |
| IF3 | MCU control, 64-byte reports, usage page `0xffa0` | `hid-lenovo-go-s` | `configure.sh`, kernel sysfs settings |
| IF4 | Vendor, 4-byte input | `hid-lenovo-go-s` | |
| IF5 | HID sensor hub: report 1 accelerometer, report 2 gyro, about 200 Hz | `hid-lenovo-go-s` or `hid-sensor-hub` | InputPlumber IMU source |
| IF6 | Gamepad report, 32 bytes | `hid-lenovo-go-s` | InputPlumber gamepad source and, with the patch, the touchpad |

Which driver claims IF5 varies between boots. InputPlumber reads it through
hidraw either way, so gyro works with both.

### Touchpad fields in the IF6 gamepad report

| Byte | Bits | Content |
|------|------|---------|
| 8 | bit 0 | Finger on the touchpad |
| 9 | bit 0 | Touchpad click |
| 10 | all | X movement since the last report, signed 8-bit |
| 11 | all | Y movement since the last report, signed 8-bit |

The gamepad report arrives about 125 times per second. A swipe across the
full touchpad width adds up to 330 to 460 units of X movement. InputPlumber's
touchpad range is 0 to 400.

### Touchpad digitizer report on IF2

Report `0x31`, 10 bytes including the report ID, as defined by the touchpad's
HID report descriptor:

| Byte | Content |
|------|---------|
| 0 | Report ID `0x31` |
| 1 | bit 0 confidence, bit 1 tip switch, bits 2 to 5 contact ID |
| 2 to 3 | X, 0 to 400, little-endian |
| 4 to 5 | Y, 0 to 400, little-endian |
| 6 to 7 | Scan time |
| 8 | Contact count |
| 9 | bits 0 to 2 buttons |

On the affected units, every report has X 400, Y 256, scan time 8, tip switch
0 and buttons 0.

## MCU command map

Commands are 64-byte output reports written to the IF3 hidraw node. The first
byte is the command, the second is the index or subcommand, and the rest is
data padded with zeros. Replies to set commands have the form
`04 <index> <status>`, where status 0 means success.

| Command | Meaning |
|---------|---------|
| `03 <index>` | Read a gamepad setting |
| `04 <index> <value>` | Write a gamepad setting |
| `05 <index>` | Read touchpad parameters. Index 1 returns `0x0320`, 2 returns `0x0190`, 3 returns 0, 4 returns 1 |
| `08 01 01` | Turn on controller vibration. The motors run for about two seconds |
| `08 03 00`, `08 03 01` | Turn touchpad vibration off or on |
| `0f` | Read RGB settings |
| `df` | Read production test data: touchpad vendor, IMU vendor (2 is Bosch), touchpad version |

Gamepad setting indexes for commands `03` and `04`:

| Index | Setting |
|-------|---------|
| `0x01` | Mode: 0 XInput, 1 DInput |
| `0x04` | Auto-sleep |
| `0x05` | IMU bypass |
| `0x06` | RGB on or off |
| `0x07` | IMU on or off |
| `0x08` | Touchpad on or off |
| `0x09` | Unknown. Writes are rejected |
| `0x0a` | OS mode: 0 Windows, 1 Linux |
| `0x10` | Poll rate |
| `0x11` | D-pad mode |
| `0x12` | Mouse wheel step |
| `0x20`, `0x21` | Purpose unknown |

The kernel driver `hid-lenovo-go-s` exposes several of these settings in sysfs
under the IF3 HID device, for example `touchpad/linux_mode` and `os_mode`. It
has no vibration setting.

## Virtual controllers

| InputPlumber target | USB ID | Recognized by the Steam client tested |
|---------------------|--------|---------------------------------------|
| `deck-uhid` (SteamOS default) | `28de:12ff` | No. Steam logs `Unrecognized controller using V1 HID protocol` |
| `deck` | `28de:1205` | Yes. Steam logs `Controller uses V1 HID protocol` and loads the Steam Deck controller configuration |

`steamos-manager` 26.4.1 reads its target from
`/usr/share/steamos-manager/devices/legion-go-s.toml` and accepts only
`deck-uhid`, `keyboard` and `mouse` there.
