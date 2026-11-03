# Legion Go S controller fixes for SteamOS

On SteamOS 3.9, the built-in controller of the Lenovo Legion Go S has three
problems: the gyro barely registers in Steam, rumble never works, and the small
touchpad does nothing. This repository fixes all three and documents what
causes them.

| Problem | Cause | What this repository does |
|---------|-------|---------------------------|
| Gyro moves less than 1 percent of what it should | InputPlumber 0.78.0, which ships with SteamOS 3.9.5, passes IMU values to Steam without scaling them | Runs InputPlumber 0.83.1, which scales them correctly |
| Steam ignores gyro, touchpad and rumble | Steam doesn't recognize the virtual controller that SteamOS selects (`deck-uhid`) | Switches InputPlumber to the `deck` virtual controller, which Steam does recognize |
| No rumble | The controller ships with vibration turned off. Only Lenovo's Windows app turns it on | Sends the enable command every time the controller connects and after resume |
| Touchpad does nothing | The touchpad's own HID report repeats one fixed frame. The real touch data arrives in the gamepad report, and InputPlumber ignores it there | Adds a small patch to InputPlumber that reads the touchpad from the gamepad report |

## Status

Tested on one Legion Go S, model 83L3, with SteamOS 3.9.5, controller
firmware 0.0.4.3 and touchpad firmware SIPO v12. On that unit:

- Touchpad movement and clicks work in Steam.
- The virtual controller reports about 1 g at rest, which is the correct gyro
  and accelerometer scale. Gyro aiming in a game hasn't been checked.
- The motors run when InputPlumber's force-feedback interface is called, as
  measured with the internal microphone. Rumble inside a game hasn't been
  checked.

Other models (83N6, 83Q2, 83Q3) use the same controller, but nobody has tested
them yet. Some units have a touchpad from a different supplier ("Better Life")
whose own report works. Before you install, run the touchpad diagnostic to see
whether your unit has the fault this patch targets:

```bash
sudo python3 -I tools/touchpad-diag.py 30
```

Touch, swipe and click the touchpad while it runs. The last line tells you
which case your touchpad is in.

## Install

You need root on the Legion Go S and a copy of this repository on it.

1. Download `inputplumber` from the [latest release](https://github.com/selfxplanatorium/legiongo-s-steamos-fixes/releases/latest)
   into `dist/`, or [build it yourself](inputplumber/README.md).
2. On the Legion Go S, run the installer from the repository root:

   ```bash
   sudo ./install.sh
   ```

The installer restarts InputPlumber, so the controller drops out for a few
seconds. The motors run for about two seconds when vibration turns on.

[Install, update and uninstall](docs/install.md) covers prerequisites,
verification and rollback in detail.

## Documentation

- [Install, update and uninstall](docs/install.md)
- [Troubleshooting](docs/troubleshooting.md)
- [How each problem was found](docs/findings.md)
- [Reference](docs/reference.md): installed files, settings, controller
  interfaces and the MCU command map
- [InputPlumber patch and build](inputplumber/README.md)
- [Changelog](CHANGELOG.md)

## Repository layout

```text
install.sh, uninstall.sh   install or remove everything
files/                     files installed under /etc
inputplumber/              the touchpad patch, a container build and its notes
tools/touchpad-diag.py     raw HID touchpad diagnostic
docs/                      documentation
```

## Upstream

The touchpad patch is meant for upstream InputPlumber. Once a release with it
reaches SteamOS, you won't need the patched build, and the deck-target and
vibration fixes stay useful until SteamOS handles those as well. Related
upstream issue:
[ShadowBlip/InputPlumber#604](https://github.com/ShadowBlip/InputPlumber/issues/604).

## License

GPL-3.0, the same license as InputPlumber, which the patch modifies. See
[LICENSE](LICENSE).
