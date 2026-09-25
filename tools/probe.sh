#!/bin/sh
# A signed-in swap, back to back a quarter second apart (about three a
# second), for the gap a deploy leaves:
#
#     UNOTES_PASSWORD=... tools/probe.sh https://unotes.fly.dev 180 > probe.txt
#
# One line per request: UTC time, status, seconds, and whether the body was
# the fragment (`frag`), a login form (`login`) or something else (`other`).
# The password is read from the environment and never printed.
set -u
base=${1%/}
seconds=$2
jar=$(mktemp)
trap 'rm -f "$jar"' EXIT
printf '%s' "$UNOTES_PASSWORD" | curl -s -o /dev/null -c "$jar" \
    --data-urlencode "user=${UNOTES_USER:-reader}" --data-urlencode "password@-" "$base/login"
end=$(( $(date +%s) + seconds ))
while [ "$(date +%s)" -lt "$end" ]; do
    out=$(curl -s -b "$jar" -H 'HX-Request-Type: partial' --max-time 15 \
        -w '\n%{http_code} %{time_total}' "$base/notes/25")
    tail=$(printf '%s' "$out" | tail -n 1)
    body=$(printf '%s' "$out" | sed '$d')
    case "$body" in
        *'class="login"'*) kind=login ;;
        '<section id="unotes"'*) kind=frag ;;
        *) kind=other ;;
    esac
    echo "$(python3 -c 'from datetime import datetime,timezone;print(datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3])') $tail $kind"
    python3 -c 'import time; time.sleep(0.25)'
done
