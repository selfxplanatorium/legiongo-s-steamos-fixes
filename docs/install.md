# Install, update and uninstall

This guide installs the fixes on a Legion Go S running SteamOS. It also covers
checking the result, what to do after SteamOS updates, and how to remove
everything.

## What the installer changes

The installer writes only to `/etc` and `/opt`. SteamOS keeps both across
system image updates, and a factory reset removes both. The read-only root
filesystem stays enabled.

| Path | Purpose |
|------|---------|
| `/opt/inputplumber-legion-go-s/inputplumber` | Patched InputPlumber binary |
| `/etc/systemd/system/inputplumber.service.d/10-legion-go-s.conf` | Makes `inputplumber.service` start the patched binary |
| `/etc/legion-go-s/configure.sh` | Turns on vibration and keeps the touchpad in absolute mode |
| `/etc/udev/rules.d/99-legion-go-s.rules` | Runs `configure.sh` when the controller connects |
| `/etc/systemd/system/legion-go-s-resume.service` | Runs `configure.sh` after suspend or hibernate |
| `/etc/legion-go-s/deck-target.sh`, `legion-go-s-deck-target.service` | Keeps InputPlumber on the `deck` virtual controller |
| `/etc/legion-go-s/check-inputplumber.sh`, `legion-go-s-inputplumber-check.service` | Logs a warning at boot when SteamOS ships a newer InputPlumber |

The SteamOS copy of InputPlumber in `/usr/bin` stays untouched. The
[reference](reference.md) describes each file in detail.

## Before you begin

You need:

- A Legion Go S (model 83L3, 83N6, 83Q2 or 83Q3) running SteamOS 3.9 or later.
- A user password, so that `sudo` works. If you haven't set one, open Konsole
  in Desktop Mode and run `passwd`.
- The patched InputPlumber binary. Download `inputplumber` from the
  [latest release](https://github.com/selfxplanatorium/legiongo-s-steamos-fixes/releases/latest),
  or [build it yourself](../inputplumber/README.md) on any x86_64 Linux
  machine with Docker.

The installer refuses to run on other hardware unless you set `FORCE=1`.

## Install the fixes

Run these steps in Konsole in Desktop Mode, or over SSH.

1. Clone the repository:

   ```bash
   git clone https://github.com/selfxplanatorium/legiongo-s-steamos-fixes.git
   cd legiongo-s-steamos-fixes
   ```

2. Put the patched binary in `dist/` and make it executable:

   ```bash
   mkdir -p dist
   cp ~/Downloads/inputplumber dist/inputplumber
   chmod 755 dist/inputplumber
   ```

   Replace `~/Downloads/inputplumber` with the path where you saved the
   binary. Skip this step if you built the binary with
   `inputplumber/build.sh`, which writes it to `dist/` already.

3. Run the installer:

   ```bash
   sudo ./install.sh
   ```

   The installer copies the files, enables the services and restarts
   InputPlumber. The controller stops responding for a few seconds. The motors
   run for about two seconds when vibration turns on.

   To install a binary from a different path, pass it as an argument:
   `sudo ./install.sh /path/to/inputplumber`.

## Check the installation

1. Check that InputPlumber runs the patched binary:

   ```bash
   systemctl show -p ExecStart --value inputplumber.service
   ```

   The output contains `path=/opt/inputplumber-legion-go-s/inputplumber`.

2. Read the log messages from the fixes:

   ```bash
   journalctl -t legion-go-s -b
   ```

   Expect lines similar to these:

   ```text
   pinned InputPlumber 0.83.1 (image ships 0.78.0)
   0003:1A86:E310.0056: configured via /dev/hidraw2 (vibration on, touchpad absolute)
   InputPlumber target set to deck+keyboard+mouse
   ```

3. Check that Steam sees a Steam Controller:

   ```bash
   lsusb | grep 28de
   ```

   The output contains `28de:1205 Valve Software Steam Controller`.

4. Test rumble without Steam:

   ```bash
   busctl --system call org.shadowblip.InputPlumber \
     /org/shadowblip/InputPlumber/CompositeDevice0 \
     org.shadowblip.Output.ForceFeedback Rumble d 1.0
   ```

   The motors run. Stop them with the same command, replacing `Rumble d 1.0`
   with `Stop`.

5. In Steam, open the controller settings and use the controller test to
   check that the touchpad responds. Menu names can differ between Steam
   client versions. Default controller layouts leave gyro off, so bind it in
   the game's controller layout to use it.

## After a SteamOS update

You normally don't need to do anything. The patched binary keeps running
because the systemd drop-in in `/etc` points to `/opt`.

At every boot, `legion-go-s-inputplumber-check.service` compares the SteamOS
InputPlumber version with the patched one. When SteamOS ships the same version
or a newer one, it logs a warning:

```bash
journalctl -t legion-go-s -p warning -b
```

When you see that warning, check the
[InputPlumber releases](https://github.com/ShadowBlip/InputPlumber/releases)
for the touchpad fix:

- If the new release includes it, [uninstall the fixes](#uninstall-the-fixes).
  Keep `configure.sh` and `deck-target.sh` only if SteamOS still lacks working
  rumble or the `deck` target.
- If it doesn't, rebuild the patch for the new version with
  `inputplumber/build.sh vX.Y.Z` (replace `vX.Y.Z` with the release tag) and
  run `sudo ./install.sh` again.

A factory reset removes everything under `/etc` and `/opt`. Run the installer
again afterwards.

## Return to the SteamOS InputPlumber temporarily

To go back to stock InputPlumber without removing the other fixes:

1. Remove the drop-in:

   ```bash
   sudo rm /etc/systemd/system/inputplumber.service.d/10-legion-go-s.conf
   ```

2. Reload systemd and restart InputPlumber:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart inputplumber
   ```

The touchpad stops working. If SteamOS still ships InputPlumber 0.78.0, the
gyro becomes too weak again. Run `sudo ./install.sh` to undo this.

## Uninstall the fixes

1. From the repository root, run:

   ```bash
   sudo ./uninstall.sh
   ```

   The script stops and removes the services, the udev rule, the scripts and
   the drop-in. It then restarts InputPlumber with the SteamOS binary.

2. Optional: Remove the patched binary:

   ```bash
   sudo rm -r /opt/inputplumber-legion-go-s
   ```

The controller can keep vibration turned on after you uninstall. In testing,
the setting survived USB power cycles and driver reloads. Whether a cold boot
resets it hasn't been tested, and this repository has no command to turn it
off.
