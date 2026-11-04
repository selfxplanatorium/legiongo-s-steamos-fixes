#!/usr/bin/env bash
# Legion Go S controller setup that must be re-applied after every controller
# enumeration (boot, USB reset, firmware flash, or a reconnect after resume):
#   1. MCU command 08 01 01: enable "vibration notify". The MCU ships with it
#      off and only Legion Space (Windows) turns it on, so rumble packets are
#      ACKed but the motors never move.
#   2. MCU command 04 08 01: touchpad enable.
#   3. Touchpad mode absolute (linux + windows). In relative mode the touchpad
#      sends nothing at all on the affected SIPO firmware.
#
# Each write of 08 01 01 buzzes the motors for ~2 s, so it runs once per HID
# device instance (udev can fire several times for one enumeration).
# Usage: configure.sh [--force]
set -u

STATE_DIR=/run/legion-go-s
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

log() { logger -t legion-go-s "$*" 2>/dev/null || true; }

# Find the IF3 (MCU control) HID device of the controller (1a86:e310 / e311).
find_mcu() {
    local d
    for d in /sys/bus/hid/devices/0003:1A86:E31[01].*; do
        [[ -e "$d" ]] || continue
        if [[ "$(readlink -f "$d")" == *":1.3/"* ]]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

mcu_cmd() {
    # $1 = hidraw node, $2.. = command bytes (hex). Pads to a 64-byte report.
    local node=$1; shift
    local bytes="" b
    for b in "$@"; do bytes+="\\x$b"; done
    { printf "%b" "$bytes"; head -c $((64 - $#)) /dev/zero; } > "$node"
}

sleep 1.5   # the MCU needs time after enumeration before it accepts commands

mcu=$(find_mcu) || { log "MCU control interface not found"; exit 0; }
id=$(basename "$mcu")
mkdir -p "$STATE_DIR"
# Serialize runs: udev and the resume/installer path can fire together.
exec 9>"$STATE_DIR/lock"
flock -w 10 9 || { log "$id: lock timeout"; exit 0; }
if [[ $FORCE -eq 0 && -e "$STATE_DIR/$id" ]]; then
    exit 0
fi

node=""
for h in "$mcu"/hidraw/hidraw*; do
    [[ -e "$h" ]] && node="/dev/$(basename "$h")"
done
if [[ -z "$node" || ! -w "$node" ]]; then
    log "$id: no writable hidraw node"
    exit 0
fi

ok=1
mcu_cmd "$node" 08 01 01 || ok=0
mcu_cmd "$node" 04 08 01 || ok=0

if [[ -d "$mcu/touchpad" ]]; then
    echo absolute > "$mcu/touchpad/linux_mode"   2>/dev/null || ok=0
    echo absolute > "$mcu/touchpad/windows_mode" 2>/dev/null || ok=0
    echo true     > "$mcu/touchpad/enabled"      2>/dev/null || ok=0
else
    log "$id: touchpad sysfs attributes missing (hung MCU? see README)"
    ok=0
fi

touch "$STATE_DIR/$id"
if [[ $ok -eq 1 ]]; then
    log "$id: configured via $node (vibration on, touchpad absolute)"
else
    log "$id: configured via $node with errors"
fi
exit 0
