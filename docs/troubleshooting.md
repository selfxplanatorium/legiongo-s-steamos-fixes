# Troubleshooting

Each section starts with a symptom and explains how to confirm the cause and
fix it. Commands need a terminal on the Legion Go S (Konsole in Desktop
Mode, or SSH).

## The controller stops responding

**Symptom:** buttons, sticks and the touchpad do nothing, and button
combinations are ignored.

1. Look for the MCU error in the kernel log:

   ```bash
   sudo dmesg | grep -i "MCU ID"
   ```

   The controller's MCU is hung if you see
   `hid-lenovo-go-s 0003:1A86:E310.xxxx: Failed to retrieve MCU ID: -16`.
   Its settings directory under `/sys/bus/hid/devices/` also disappears. This
   happened after repeated USB resets during testing.

2. Reload the controller driver:

   ```bash
   sudo modprobe -r hid_lenovo_go_s
   sleep 2
   sudo modprobe hid_lenovo_go_s
   ```

   A cold boot also clears the hang.

3. Turn vibration back on:

   ```bash
   sudo /etc/legion-go-s/configure.sh --force
   ```

## No rumble

**Symptom:** games and Steam send rumble, but the motors don't move.

1. Test the motors through InputPlumber, without Steam:

   ```bash
   busctl --system call org.shadowblip.InputPlumber \
     /org/shadowblip/InputPlumber/CompositeDevice0 \
     org.shadowblip.Output.ForceFeedback Rumble d 1.0
   ```

   Stop them by running the same command with `Stop` in place of
   `Rumble d 1.0`.

2. If the motors stay still, send the vibration enable command again:

   ```bash
   sudo /etc/legion-go-s/configure.sh --force
   ```

   The motors run for about two seconds, which confirms that the controller
   accepted the command. Check the result in `journalctl -t legion-go-s -b`.

3. If step 1 works but games still don't rumble, check that Steam uses the
   `deck` virtual controller. See
   [Steam ignores gyro, touchpad or rumble](#steam-ignores-gyro-touchpad-or-rumble).

Don't run `configure.sh --force` in a loop or from a timer. Every run makes the
motors buzz for two seconds.

## The touchpad does nothing

**Symptom:** touching or clicking the small touchpad has no effect in Steam or
on the desktop.

1. Check that InputPlumber runs the patched binary:

   ```bash
   systemctl show -p ExecStart --value inputplumber.service
   ```

   The output must contain `/opt/inputplumber-legion-go-s/inputplumber`. If it
   shows `/usr/bin/inputplumber`, run `sudo ./install.sh` again. An old drop-in
   in `/etc/systemd/system/inputplumber.service.d/` with a name that sorts
   after `10-legion-go-s.conf` overrides it, so remove such files.

2. Check the touchpad mode:

   ```bash
   cat /sys/bus/hid/devices/0003:1A86:E31*/touchpad/linux_mode
   ```

   It must be `absolute`. In `relative` mode, this touchpad sends no data at
   all. Fix it with `sudo /etc/legion-go-s/configure.sh --force`.

3. Run the diagnostic while you touch, swipe and click the touchpad:

   ```bash
   sudo python3 -I tools/touchpad-diag.py 30
   ```

   The result line tells you which case applies:

   | Result | Meaning |
   |--------|---------|
   | IF2 digitizer frozen, gamepad report carries live motion | The fault this patch fixes. Recheck steps 1 and 2 |
   | gamepad report carries motion and IF2 also changes | Your touchpad's own report works. Stock InputPlumber may handle it, and the patch may double the input. Disable the patch path, as described in the [reference](reference.md#patched-inputplumber-settings) |
   | no touch seen in the gamepad report | The touchpad is off or in relative mode, or the diagnostic missed your touches. Recheck step 2 and run it again |
   | touches seen without motion | The gamepad report shows the finger but no movement. This case hasn't been seen on the test unit. Open an issue with the diagnostic output |

4. In Steam's game mode UI and overlay, the touchpad acts as a mouse only
   while you hold the Guide button. The InputPlumber maintainer describes
   this Steam behavior in
   [ShadowBlip/InputPlumber#604](https://github.com/ShadowBlip/InputPlumber/issues/604).

## The touchpad is too slow or too fast

Set a gain for the touchpad movement. The default is `1.0`.

1. Create a drop-in, for example
   `/etc/systemd/system/inputplumber.service.d/20-touchpad.conf`:

   ```ini
   [Service]
   Environment=INPUTPLUMBER_LEGION_GO_S_GAMEPAD_TOUCHPAD_GAIN=1.5
   ```

2. Restart InputPlumber:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart inputplumber
   ```

## Steam ignores gyro, touchpad or rumble

**Symptom:** InputPlumber works, but Steam doesn't react to gyro, the touchpad
or rumble.

1. Check which virtual controller InputPlumber presents:

   ```bash
   lsusb | grep 28de
   ```

   `28de:1205 Valve Software Steam Controller` is correct. `28de:12ff`, or no
   entry at all, means that the `deck` target isn't active.

2. Check the target service:

   ```bash
   systemctl status legion-go-s-deck-target
   journalctl -t legion-go-s -b
   ```

3. Restart it if needed:

   ```bash
   sudo systemctl restart legion-go-s-deck-target
   ```

Don't try to set `deck` in `steamos-manager`'s device configuration. Its
configuration accepts only `deck-uhid`, `keyboard` and `mouse`, and the value
`deck` makes the daemon fail on every start.

## Gyro barely moves

**Symptom:** gyro aiming works, but large wrist movements produce tiny camera
movements.

Check which InputPlumber runs (step 1 in
[The touchpad does nothing](#the-touchpad-does-nothing)). InputPlumber 0.78.0
from SteamOS 3.9.5 sends gyro values at less than 1 percent of the correct
scale. The patched build is based on 0.83.1, which fixes this.

Also check that gyro is bound in the game's Steam controller layout. Default
layouts leave it off.
