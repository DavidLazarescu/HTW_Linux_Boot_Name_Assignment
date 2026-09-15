#!/bin/bash
#
# Erzeugt /etc/fog-hostnames.map aus der Hostliste des FOG-Servers,
# damit die Namen nicht doppelt gepflegt werden muessen.
#
# Voraussetzung (FOG 1.5.x):
#   FOG Configuration -> FOG Settings -> API System      -> fog-api-token
#   Users -> <dein User> -> API-Tab ("User API Enable")  -> fog-user-token
#
# Aufruf:
#   FOG_SERVER=http://fogserver FOG_API_TOKEN=... FOG_USER_TOKEN=... \
#       ./make-map-from-fog.sh [filter] > fog-hostnames.map
#
# [filter] ist ein optionaler grep-Ausdruck auf den Hostnamen, z.B. '^g530-'
#
set -euo pipefail

: "${FOG_SERVER:?FOG_SERVER nicht gesetzt (z.B. http://fogserver)}"
: "${FOG_API_TOKEN:?FOG_API_TOKEN nicht gesetzt}"
: "${FOG_USER_TOKEN:?FOG_USER_TOKEN nicht gesetzt}"
filter="${1:-.}"

command -v jq >/dev/null || { echo "jq fehlt: sudo apt install jq" >&2; exit 1; }

printf '# Erzeugt am %s aus %s\n' "$(date '+%F %T')" "$FOG_SERVER"
printf '# %-19s %s\n' "MAC" "HOSTNAME"

curl -fsS \
     -H "fog-api-token: $FOG_API_TOKEN" \
     -H "fog-user-token: $FOG_USER_TOKEN" \
     "$FOG_SERVER/fog/host" \
| jq -r '.hosts[] | . as $h
         | ([$h.primac] + (($h.macs // []) | map(if type=="object" then .mac else . end)))
         | unique[] | select(. != null and . != "")
         | "\(.) \($h.name)"' \
| awk -v f="$filter" 'tolower($2) ~ tolower(f) { printf "%-20s %s\n", tolower($1), tolower($2) }' \
| sort -u
