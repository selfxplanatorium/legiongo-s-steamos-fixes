#!/usr/bin/env bash
# Remove the Legion Go S fixes and return to the SteamOS image's InputPlumber.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }
systemctl disable --now legion-go-s-deck-target.service 2>/dev/null || true
systemctl disable legion-go-s-resume.service legion-go-s-inputplumber-check.service 2>/dev/null || true
rm -f /etc/systemd/system/legion-go-s-deck-target.service \
      /etc/systemd/system/legion-go-s-resume.service \
      /etc/systemd/system/legion-go-s-inputplumber-check.service \
      /etc/systemd/system/inputplumber.service.d/10-legion-go-s.conf \
      /etc/udev/rules.d/99-legion-go-s.rules
rm -f /etc/legion-go-s/configure.sh /etc/legion-go-s/deck-target.sh /etc/legion-go-s/check-inputplumber.sh
rmdir /etc/legion-go-s 2>/dev/null || true
systemctl daemon-reload
udevadm control --reload
systemctl restart inputplumber.service
echo "removed. /opt/inputplumber-legion-go-s is kept; delete it manually if unwanted."
echo "The controller may keep vibration enabled; this script does not turn it off."
