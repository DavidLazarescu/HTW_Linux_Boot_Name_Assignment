#!/bin/bash
# Installiert den Hostname-Fixer auf dem Mutter-PC (wird mit ins Image gecapturet).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo ausfuehren." >&2; exit 1; }
src="$(cd "$(dirname "$0")" && pwd)"

install -m 0755 "$src/fog-set-hostname"        /usr/local/sbin/fog-set-hostname
install -m 0644 "$src/fog-set-hostname.service" /etc/systemd/system/fog-set-hostname.service

if [ -f /etc/fog-hostnames.map ]; then
    echo "/etc/fog-hostnames.map existiert bereits -> wird NICHT ueberschrieben."
    echo "Neue Vorlage liegt unter /etc/fog-hostnames.map.new"
    install -m 0644 "$src/fog-hostnames.map" /etc/fog-hostnames.map.new
else
    install -m 0644 "$src/fog-hostnames.map" /etc/fog-hostnames.map
fi

# --- Steht die eigene MAC schon in der Tabelle? ----------------------------
own_missing=1
own_line=""
for dev in /sys/class/net/*; do
    [ -e "$dev/device" ] || continue
    mac="$(tr 'A-Z' 'a-z' <"$dev/address")"
    [ -n "$own_line" ] || own_line="$mac"
    if grep -iE "^[[:space:]]*${mac//:/[:-]}[[:space:]]" /etc/fog-hostnames.map >/dev/null 2>&1; then
        own_missing=0
    fi
done

systemctl daemon-reload
systemctl enable fog-set-hostname.service

echo
if [ "$own_missing" -eq 1 ]; then
    cat <<WARN
!! ACHTUNG: Die MAC dieses Mutter-PCs steht NICHT in /etc/fog-hostnames.map.
!! Beim naechsten Boot wuerde er in 'cse-g530-unreg-*' umbenannt.
!! Zeile ergaenzen (Namen ggf. anpassen):
!!
!!     $own_line   cse-g530-00
!!
WARN
fi
echo "Installiert. Naechste Schritte:"
echo "  1) MAC-Liste pflegen:  sudoedit /etc/fog-hostnames.map"
echo "  2) Testlauf:           sudo /usr/local/sbin/fog-set-hostname ; hostnamectl"
echo "  3) Vor dem Capture:    sudo $src/pre-capture-cleanup.sh"
