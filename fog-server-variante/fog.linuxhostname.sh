#!/bin/bash
##
## /images/postdownloadscripts/fog.linuxhostname.sh
##
## Setzt nach dem Deploy den Hostnamen im frisch geschriebenen Linux-System
## auf den in FOG hinterlegten Hostnamen ($hostname) und entfernt geklonte
## Identitaeten (machine-id, SSH-Host-Keys).
##
## Einbinden: in /images/postdownloadscripts/fog.postdownload folgende Zeile
##   . ${postdownpath}fog.linuxhostname.sh
## Beide Dateien: chmod 755, chown fogproject:apache (bzw. www-data).
##
## Achtung: wird von FOS gesourct -> 'return' statt 'exit', kein 'set -e'.
##

if [ -z "$hostname" ]; then
    echo "fog.linuxhostname: kein \$hostname vom Server -> uebersprungen"
    return 0
fi

lh_mnt="/mnt/linuxroot"
mkdir -p "$lh_mnt"
lh_done=0

for lh_part in $(lsblk -pnlo NAME,TYPE "$hd" 2>/dev/null | awk '$2=="part"{print $1}'); do
    [ "$lh_done" -eq 1 ] && break
    mount "$lh_part" "$lh_mnt" >/dev/null 2>&1 || continue

    # Root-Partition erkennen: /etc/fstab + /etc/hostname vorhanden
    if [ -f "$lh_mnt/etc/fstab" ] && [ -d "$lh_mnt/etc" ]; then
        echo "fog.linuxhostname: Root-Partition $lh_part -> Hostname '$hostname'"

        echo "$hostname" > "$lh_mnt/etc/hostname"

        if grep -qE '^[[:space:]]*127\.0\.1\.1[[:space:]]' "$lh_mnt/etc/hosts" 2>/dev/null; then
            sed -ri "s/^([[:space:]]*127\.0\.1\.1[[:space:]]+).*/\1$hostname/" "$lh_mnt/etc/hosts"
        else
            printf '127.0.1.1\t%s\n' "$hostname" >> "$lh_mnt/etc/hosts"
        fi

        # GNOME "Geraetename" des Mutter-PCs
        rm -f "$lh_mnt/etc/machine-info"

        # eindeutige machine-id erzwingen (leere Datei -> systemd erzeugt neu)
        : > "$lh_mnt/etc/machine-id"
        rm -f "$lh_mnt/var/lib/dbus/machine-id"
        ln -sf /etc/machine-id "$lh_mnt/var/lib/dbus/machine-id" 2>/dev/null

        # SSH-Host-Keys: werden beim ersten Boot von ssh-keygen -A neu erzeugt
        rm -f "$lh_mnt"/etc/ssh/ssh_host_*

        # alte DHCP-Leases
        rm -f "$lh_mnt"/var/lib/dhcp/*.leases "$lh_mnt"/var/lib/NetworkManager/*.lease 2>/dev/null

        lh_done=1
    fi

    umount "$lh_mnt" >/dev/null 2>&1
done

[ "$lh_done" -eq 1 ] || echo "fog.linuxhostname: WARNUNG - keine Linux-Root-Partition auf $hd gefunden"
