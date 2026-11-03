#!/usr/bin/env bash
# Warn when the SteamOS image ships an InputPlumber that is at least as new as
# the pinned patched build, so the pin can be rebased or removed.
set -u
PINNED=/opt/inputplumber-legion-go-s/inputplumber
STOCK=/usr/bin/inputplumber
ver() { "$1" --version 2>/dev/null | awk '{print $2}'; }

[[ -x "$PINNED" ]] || exit 0
p=$(ver "$PINNED"); s=$(ver "$STOCK")
[[ -n "$p" && -n "$s" ]] || exit 0
newest=$(printf '%s\n%s\n' "$p" "$s" | sort -V | tail -1)
if [[ "$s" == "$p" || "$newest" == "$s" ]]; then
    logger -t legion-go-s -p user.warning \
        "SteamOS InputPlumber $s >= pinned patched build $p: check whether the touchpad fix is upstream, then rebase or remove /etc/systemd/system/inputplumber.service.d/10-legion-go-s.conf"
else
    logger -t legion-go-s "pinned InputPlumber $p (image ships $s)"
fi
