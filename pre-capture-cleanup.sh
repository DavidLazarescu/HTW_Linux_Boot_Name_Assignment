#!/bin/bash
#
# pre-capture-cleanup.sh -- "Sysprep" fuer den Mutter-PC.
#
# UNMITTELBAR vor dem Upload des Images ausfuehren und den Rechner danach
# SOFORT herunterfahren (nicht mehr normal booten!). Beim naechsten normalen
# Boot wuerden machine-id/SSH-Keys neu erzeugt und der Sysprep-Marker
# geloescht -- dann muesste das Skript vor dem Capture erneut laufen.
#
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo ausfuehren." >&2; exit 1; }

say() { printf '  * %s\n' "$*"; }

echo "== Pre-Capture-Cleanup =="

# --- 0. Sanity-Checks -------------------------------------------------------
if [ ! -x /usr/local/sbin/fog-set-hostname ]; then
    echo "FEHLER: /usr/local/sbin/fog-set-hostname fehlt (install.sh vergessen?)" >&2
    exit 1
fi
if ! systemctl is-enabled --quiet fog-set-hostname.service; then
    echo "FEHLER: fog-set-hostname.service ist nicht enabled." >&2
    exit 1
fi
if [ ! -s /etc/fog-hostnames.map ] || ! grep -qvE '^[[:space:]]*(#|$)' /etc/fog-hostnames.map; then
    echo "FEHLER: /etc/fog-hostnames.map ist leer bzw. enthaelt nur Kommentare." >&2
    exit 1
fi
say "fog-set-hostname installiert und aktiviert"

# Steht die eigene MAC in der Liste?
own_missing=1
for dev in /sys/class/net/*; do
    [ -e "$dev/device" ] || continue
    mac="$(tr 'A-Z' 'a-z' <"$dev/address")"
    if grep -iE "^[[:space:]]*${mac//:/[:-]}[[:space:]]" /etc/fog-hostnames.map >/dev/null 2>&1; then
        own_missing=0
    fi
done
if [ "$own_missing" -eq 1 ]; then
    echo "  ! WARNUNG: die MAC dieses Mutter-PCs steht nicht in /etc/fog-hostnames.map."
    echo "  ! Er bekommt beim naechsten Boot einen 'unregistriert-*'-Namen."
fi

# --- 1. Hostname neutralisieren --------------------------------------------
echo "fog-image-template" >/etc/hostname
sed -ri 's/^([[:space:]]*127\.0\.1\.1[[:space:]]+).*/\1fog-image-template/' /etc/hosts
rm -f /etc/machine-info                       # GNOME "Pretty Hostname"
say "Hostname im Image auf 'fog-image-template' gesetzt"

# --- 2. SSH-Host-Keys entfernen (werden beim ersten Boot neu erzeugt) ------
rm -f /etc/ssh/ssh_host_*
say "SSH-Host-Keys geloescht"

# --- 3. DHCP-Leases und NetworkManager-Zustand ------------------------------
rm -f /var/lib/dhcp/*.leases /var/lib/dhcp/*.leases~ 2>/dev/null || true
rm -f /var/lib/NetworkManager/*.lease /var/lib/NetworkManager/*.state 2>/dev/null || true
rm -f /var/lib/systemd/random-seed 2>/dev/null || true
say "DHCP-Leases / Random-Seed entfernt"

# --- 4. Logs und Caches ------------------------------------------------------
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
rm -f /var/log/fog-set-hostname.log
apt-get clean >/dev/null 2>&1 || true
say "Journal geleert, apt-Cache geleert"

# --- 5. Sysprep-Marker -------------------------------------------------------
date '+%Y-%m-%d %H:%M:%S' >/etc/fog-image-sysprepped
say "Marker /etc/fog-image-sysprepped gesetzt"

# --- 6. machine-id zuletzt: leere Datei -> systemd erzeugt beim Boot eine neue
# (Leer lassen, NICHT loeschen -- so dokumentiert es systemd fuer Images.)
: >/etc/machine-id
if [ -e /var/lib/dbus/machine-id ] && [ ! -L /var/lib/dbus/machine-id ]; then
    ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi
say "machine-id geleert (wird pro Rechner neu erzeugt)"

cat <<'MSG'

Fertig. JETZT sofort ausschalten und das Image capturen:

    sudo poweroff

Danach in FOG den Capture-Task starten. Nicht vorher noch einmal in den
Desktop booten -- sonst muss dieses Skript erneut laufen.
MSG
