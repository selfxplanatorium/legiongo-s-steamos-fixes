# Changelog

## v0.83.1-gos1 (2026-11-04)

First release.

### Added

- Patched InputPlumber 0.83.1 that reads the touchpad from the gamepad
  report. Touchpad movement and clicks work in Steam on units whose touchpad
  report stays frozen.
- `configure.sh`, with a udev rule and a resume service. It turns on
  controller vibration and keeps the touchpad in absolute mode.
- `deck-target.sh` with its service, which keeps InputPlumber on the `deck`
  virtual controller that Steam recognizes.
- A boot-time check that logs a warning when SteamOS ships an InputPlumber at
  least as new as the patched build.
- `install.sh` and `uninstall.sh`.
- `tools/touchpad-diag.py`, a raw HID touchpad diagnostic.

### Release binary

`inputplumber`, built with `inputplumber/build.sh v0.83.1`.

SHA-256: `cf4f2254b8b48acf0a3ecfabe0d41d4cc69841300bfa939b6ed960cbe6dc0787`

### Compatibility

Tested on a Legion Go S 83L3 with SteamOS 3.9.5, controller firmware 0.0.4.3
and SIPO touchpad firmware v12. Needs glibc 2.39 or newer.
