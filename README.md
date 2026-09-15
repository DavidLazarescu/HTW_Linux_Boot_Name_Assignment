# Hostnamen nach FOG-Deploy automatisch setzen (Raum G530)

## Problem

Ein FOG-Image ist ein 1:1-Klon des Mutter-PCs. Unter Windows setzt der
FOG-Client (HostnameChanger) den Namen nach dem Deploy neu -- unter Linux
gibt es dafuer praktisch keine funktionierende Loesung, deshalb heissen nach
dem Pull alle Rechner wie der Mutter-PC.

Mitgeklont werden ausserdem:

| Was | Folge |
|---|---|
| `/etc/hostname`, `127.0.1.1` in `/etc/hosts` | alle heissen gleich, `sudo` haengt |
| `/etc/machine-id` | **alle senden dieselbe DHCP-Client-ID** -> feste IPs/Reservierungen greifen nicht mehr zuverlaessig, journald-IDs kollidieren |
| `/etc/ssh/ssh_host_*` | alle Rechner haben denselben SSH-Fingerprint |
| `/etc/machine-info` | GNOME zeigt weiter den "Geraetenamen" des Mutter-PCs |

Diese Loesung behebt alle vier Punkte.

## Loesungsweg

Ein systemd-Oneshot-Dienst im Image liest beim Boot die MAC der ersten
physischen NIC, schlaegt sie in `/etc/fog-hostnames.map` nach und setzt den
Hostnamen -- **bevor** NetworkManager DHCP spricht und bevor der
Display-Manager startet. Laeuft bei jedem Boot und ist idempotent.

MAC statt IP, weil die MAC schon vor dem Netzwerkstart feststeht (die IP
kommt ja erst per DHCP, teilweise sogar abhaengig vom Hostnamen).

## Dateien

| Datei | Ziel | Zweck |
|---|---|---|
| `fog-set-hostname` | `/usr/local/sbin/` | das eigentliche Skript |
| `fog-set-hostname.service` | `/etc/systemd/system/` | systemd-Oneshot |
| `fog-hostnames.map` | `/etc/` | MAC -> Hostname Tabelle (22 PCs, fertig) |
| `install.sh` | -- | installiert + enabled alles |
| `pre-capture-cleanup.sh` | -- | "Sysprep" vor dem Image-Upload |
| `make-map-from-fog.sh` | -- | erzeugt die Tabelle aus der FOG-API |
| `fog-server-variante/` | FOG-Server | Alternative als Post-Download-Script |

## Was das Skript ersetzt

Die bisherige Handarbeit auf jedem der 22 Rechner nach jedem Deploy:

```bash
sudo hostnamectl set-hostname cse-g530-xxl
sudo nano /etc/hosts        # 127.0.1.1 cse-g530-00  ->  cse-g530-xxl
```

Genau das macht `fog-set-hostname` beim Boot automatisch, anhand der MAC.
`/etc/fog-hostnames.map` enthaelt bereits alle 22 Rechner (Stand 10.09.2026);
zu ergaenzen ist nur noch die MAC des Mutter-PCs selbst.

## Einrichtung (einmalig, auf dem Mutter-PC)

```bash
scp -r fog-hostname/ mutter-pc:/tmp/
ssh mutter-pc
cd /tmp/fog-hostname
sudo ./install.sh
sudoedit /etc/fog-hostnames.map      # nur noch die MAC des Mutter-PCs eintragen
```

Tabelle testen, ohne etwas zu veraendern, geht mit einem Fake-Root:

```bash
sudo FOG_SYSROOT=/tmp/testroot FOG_FAKE_MACS="6c:3c:8c:3a:9d:a4" \
     /usr/local/sbin/fog-set-hostname
```

Echter Testlauf auf dem Mutter-PC:

```bash
sudo /usr/local/sbin/fog-set-hostname && hostnamectl
```

## Ablauf bei jedem neuen Image

```bash
# 1. Mutter-PC updaten, neue Software installieren
# 2. ggf. /etc/fog-hostnames.map ergaenzen (neue Rechner im Raum)
# 3. Sysprep + sofort ausschalten
sudo /tmp/fog-hostname/pre-capture-cleanup.sh
sudo poweroff
# 4. In FOG den Capture-Task starten, danach per WOL auf G530 deployen
```

Wichtig: nach dem Cleanup **nicht** noch einmal in den Desktop booten --
dabei werden machine-id und SSH-Keys neu erzeugt und der Sysprep-Marker
verbraucht; das Cleanup muesste dann erneut laufen.

## Kontrolle nach dem Deploy

```bash
hostnamectl
journalctl -u fog-set-hostname
cat /var/log/fog-set-hostname.log
```

Ein Rechner, dessen MAC nicht in der Tabelle steht, heisst danach
`cse-g530-unreg-<letzte 3 MAC-Oktette>` -- faellt sofort auf und kollidiert
nicht mit anderen.

## Tabelle aus FOG erzeugen statt abtippen

Wenn die Namen in FOG schon korrekt gepflegt sind:

```bash
FOG_SERVER=http://fogserver \
FOG_API_TOKEN=... FOG_USER_TOKEN=... \
./make-map-from-fog.sh '^cse-g530-' | sudo tee /etc/fog-hostnames.map
```

Tokens: *FOG Configuration -> FOG Settings -> API System* (api-token) und
*Users -> \<User\> -> API* (user-token, "User API Enable" anhaken).

## Alternative: Post-Download-Script auf dem FOG-Server

Wenn du Shell-Zugriff auf den FOG-Server hast, ist das die sauberere
Variante: FOS setzt den Namen direkt nach dem Schreiben des Images, die
Namen kommen aus der FOG-Datenbank (eine einzige Quelle, kein neues Image
noetig, wenn ein Rechner dazukommt).

```bash
# auf dem FOG-Server
cp fog-server-variante/fog.linuxhostname.sh /images/postdownloadscripts/
cd /images/postdownloadscripts
echo '. ${postdownpath}fog.linuxhostname.sh' >> fog.postdownload
chmod 755 fog.postdownload fog.linuxhostname.sh
chown fogproject:apache fog.postdownload fog.linuxhostname.sh   # ggf. www-data
```

Verfuegbare Variablen dort: `$hostname`, `$mac`, `$hd`, `$disks`, `$img`,
`$osid`, `${postdownpath}`.

Beides parallel zu betreiben ist unproblematisch und sogar sinnvoll:
Post-Download setzt den Namen beim Deploy, der systemd-Dienst korrigiert ihn
bei jedem weiteren Boot.

## Warum nicht der FOG-Client unter Linux?

Es gibt ihn (Mono/`/opt/fog-service`), aber: er haengt an einer
Mono-Installation, die auf aktuellen Ubuntu-Versionen zunehmend
problematisch ist, der HostnameChanger blockt bei angemeldeten Benutzern
(Autologin!), und in mehreren Foren-Threads laufen Module/Snapins erst nach
dem ersten Login. Fuer "Name muss vor dem Login stimmen" ist das die
schlechteste der drei Optionen.
