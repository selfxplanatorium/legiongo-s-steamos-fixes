#!/usr/bin/env bash
# Install the Legion Go S fixes on SteamOS. Run as root from the repo root.
# Usage: sudo ./install.sh [path/to/patched/inputplumber]   (default: dist/inputplumber)
# Everything lands in /etc and /opt, which survive SteamOS image updates.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-$ROOT/dist/inputplumber}
OPT=/opt/inputplumber-legion-go-s

[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }
vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
case "$vendor/$product" in
    LENOVO/83L3|LENOVO/83N6|LENOVO/83Q2|LENOVO/83Q3) ;;
    *) if [[ "${FORCE:-0}" != 1 ]]; then
           echo "not a Legion Go S ($vendor $product); set FORCE=1 to install anyway" >&2; exit 1
       fi ;;
esac
[[ -x "$BIN" ]] || { echo "patched inputplumber binary not found: $BIN" >&2; exit 1; }
"$BIN" --version >/dev/null || { echo "$BIN does not run on this system" >&2; exit 1; }

echo "installing $("$BIN" --version) to $OPT"
mkdir -p "$OPT"
[[ -f "$OPT/inputplumber" ]] && cp -a "$OPT/inputplumber" "$OPT/inputplumber.prev"
install -m 755 "$BIN" "$OPT/inputplumber.new" && mv -f "$OPT/inputplumber.new" "$OPT/inputplumber"

install -d /etc/legion-go-s /etc/systemd/system/inputplumber.service.d
install -m 755 "$ROOT"/files/etc/legion-go-s/*.sh /etc/legion-go-s/
install -m 644 "$ROOT"/files/etc/udev/rules.d/99-legion-go-s.rules /etc/udev/rules.d/
install -m 644 "$ROOT"/files/etc/systemd/system/legion-go-s-*.service /etc/systemd/system/
install -m 644 "$ROOT"/files/etc/systemd/system/inputplumber.service.d/10-legion-go-s.conf \
    /etc/systemd/system/inputplumber.service.d/

systemctl daemon-reload
udevadm control --reload
systemctl enable legion-go-s-deck-target.service legion-go-s-resume.service \
    legion-go-s-inputplumber-check.service
systemctl restart inputplumber.service
systemctl restart legion-go-s-deck-target.service
systemctl start legion-go-s-inputplumber-check.service
# Runs once per controller enumeration (the InputPlumber restart above may
# already have triggered it through udev).
/etc/legion-go-s/configure.sh

echo "done. Running: $(systemctl show -p ExecStart --value inputplumber.service | grep -o 'path=[^ ;]*')"
echo "logs: journalctl -t legion-go-s -b"
