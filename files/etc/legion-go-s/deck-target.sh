#!/usr/bin/env bash
# Keep InputPlumber's composite device on the VHCI "deck" target.
#
# steamos-manager sets the target to "deck-uhid" (USB 28de:12ff) whenever
# InputPlumber starts. The Steam client tested here reports that device as
# "Unrecognized controller using V1 HID protocol" and never performs the HID
# handshake, so gyro, trackpads and rumble are unavailable in Steam Input.
# The VHCI "deck" target (USB 28de:1205) is recognised as a Steam Controller.
# steamos-manager's config only accepts deck-uhid|keyboard|mouse ("deck" makes
# it fail to parse), so this loop re-applies "deck" whenever it is replaced.
# "keyboard" and "mouse" are added so desktop mode keeps a pointer/keyboard.
set -u
BUS=org.shadowblip.InputPlumber
CD=/org/shadowblip/InputPlumber/CompositeDevice0
IFACE=org.shadowblip.Input.CompositeDevice

while true; do
    path=$(busctl --system get-property "$BUS" "$CD" "$IFACE" TargetDevices 2>/dev/null \
        | grep -o '/org/shadowblip[^ "]*')
    type=""
    for p in $path; do
        t=$(busctl --system get-property "$BUS" "$p" org.shadowblip.Input.Target DeviceType 2>/dev/null | tr -d '"')
        [[ "$t" == "s deck" ]] && type=deck
    done
    if [[ -n "$path" && "$type" != "deck" ]]; then
        if busctl --system call "$BUS" "$CD" "$IFACE" SetTargetDevices as 3 deck keyboard mouse >/dev/null 2>&1; then
            logger -t legion-go-s "InputPlumber target set to deck+keyboard+mouse"
        fi
    fi
    sleep 2
done
