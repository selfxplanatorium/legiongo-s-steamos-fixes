# InputPlumber touchpad patch

`0001-legion-go-s-touchpad-from-gamepad-report.patch` makes InputPlumber read
the Legion Go S touchpad from the gamepad report. It applies to InputPlumber
0.83.1 and to the `main` branch as of November 2026.

## What the patch changes

The patch touches two files:

- `src/drivers/legion_go_s/xinput_driver.rs`: when the gamepad report shows a
  finger on the touchpad, the driver places a position at the center of the
  touchpad. Each report's X and Y movement then moves that position, limited
  to the 0 to 400 range that the existing touchpad code uses. The driver emits
  a touchpad event whenever the finger lands, lifts or moves. A change of the
  click bit emits a right trackpad press and a pad force value, because the
  `deck` target needs a force value to register a click.
- `src/input/source/hidraw/legion_go_s/xinput.rs`: adds the right trackpad
  motion, right trackpad press and right trackpad force capabilities to the
  gamepad source, so the composite device routes the new events.

On the affected units, the touchpad's own source (IF2) sends no events,
because its report never changes. The two sources therefore don't compete.
On a unit whose IF2 report works, both sources could send touchpad events. To
turn off the new path there, set `INPUTPLUMBER_LEGION_GO_S_GAMEPAD_TOUCHPAD=0`.
The [reference](../docs/reference.md#patched-inputplumber-settings) lists both
settings.

## Build the binary

You need Docker and Git on an x86_64 Linux machine. The build doesn't need
Rust installed on the host.

1. From the repository root, run the build script:

   ```bash
   inputplumber/build.sh
   ```

   The script clones InputPlumber `v0.83.1` into `build/`, applies the patch,
   builds a container image with Rust 1.92 and the build dependencies, and
   compiles a release binary. The first run takes about seven minutes.

2. Check the result:

   ```bash
   dist/inputplumber --version
   sha256sum dist/inputplumber
   ```

   The version is `inputplumber 0.83.1`. Two clean builds of this repository
   produced the same SHA-256 hash, so you can compare yours with the hash
   published with the release.

To build against another InputPlumber release, pass its tag, for example
`inputplumber/build.sh v0.84.0`. The script stops if the patch doesn't apply.
Remove `build/InputPlumber` before switching tags.

The container uses a Debian-based Rust image, so the binary needs glibc 2.39
or newer. SteamOS 3.9.5 has glibc 2.43.
