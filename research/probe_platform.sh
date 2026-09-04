#!/usr/bin/env bash
# Settle the question this contribution actually hinges on:
#
#   Is Danderyd served by a shared platform that upstream ALREADY supports?
#
# Upstream's own list of common mistakes has this at #5: "Provider already covered
# by a shared platform. Check first." If the answer is yes, no new source module
# should be written at all — see the verdict printed at the end.
#
# Run this on any machine that can reach danderyd.se. Read-only: it fetches public
# pages and sends one address search. No credentials, nothing stored.
#
#   bash research/probe_platform.sh

set -uo pipefail

PAGE="https://www.danderyd.se/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/nar-hamtas-mitt-avfall/"
SHORT="https://www.danderyd.se/avfallsschema"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
OUT="${TMPDIR:-/tmp}/danderyd-probe"
mkdir -p "$OUT"

get() { curl -sSL --max-time 25 -A "$UA" "$1" 2>/dev/null; }
hr()  { printf '%s\n' "----------------------------------------------------------------"; }

echo "==> 1. fetching the calendar page and its JavaScript"
: > "$OUT/all.txt"
for u in "$PAGE" "$SHORT"; do get "$u" >> "$OUT/all.txt"; done

if ! [ -s "$OUT/all.txt" ]; then
  echo "    FAILED: could not reach danderyd.se from this machine."
  echo "    Run this somewhere with normal internet access."
  exit 1
fi

# Pull in same-origin and third-party scripts, where the endpoint usually lives.
grep -oE 'src="[^"]+\.js[^"]*"' "$OUT/all.txt" \
  | sed -E 's/^src="//; s/"$//' | sort -u | head -40 > "$OUT/scripts.txt"
while read -r js; do
  case "$js" in
    //*)  js="https:$js" ;;
    /*)   js="https://www.danderyd.se$js" ;;
    http*) ;;
    *)    js="https://www.danderyd.se/$js" ;;
  esac
  get "$js" >> "$OUT/all.txt"
done < "$OUT/scripts.txt"

echo "    $(wc -c < "$OUT/all.txt") bytes of page + script text collected"
hr

echo "==> 2. fingerprinting against shared platforms upstream already supports"
FOUND=""

# --- EDP Future / FutureWeb (upstream: edpevent_se, 44 tenants incl. Nacka, Roslagsvatten)
if grep -qiE 'SimpleWastePickup|FutureWeb|SearchAdress|GetWastePickupSchedule' "$OUT/all.txt"; then
  echo "    HIT: EDP FutureWeb markers present"
  grep -ohiE 'https?://[A-Za-z0-9._-]+/[A-Za-z/]*FutureWeb[A-Za-z]*/SimpleWastePickup' "$OUT/all.txt" | sort -u
  FOUND="edpevent"
fi

# --- Avfallsappen / Nova (upstream: avfallsapp_se, incl. Upplands-Bro)
if grep -qiE 'avfallsapp\.se|/wp-json/nova/v1|/api/nova/v1' "$OUT/all.txt"; then
  echo "    HIT: Avfallsappen (Nova) markers present"
  grep -ohiE 'https?://[A-Za-z0-9._-]*avfallsapp\.se[^"'"'"' ]*' "$OUT/all.txt" | sort -u
  FOUND="avfallsapp"
fi

# --- an ICS feed would make this a ~20-line YAML entry instead of any Python at all
if grep -qiE '\.ics|webcal:|iCal|Prenumerera' "$OUT/all.txt"; then
  echo "    HIT: possible calendar-subscription markers"
  grep -ohiE 'https?://[^"'"'"' ]*\.ics[^"'"'"' ]*|webcal://[^"'"'"' ]*' "$OUT/all.txt" | sort -u | head
  FOUND="${FOUND:-ics}"
fi

[ -n "$FOUND" ] || echo "    no shared-platform markers found in the static page text"
hr

echo "==> 3. probing candidate EDP FutureWeb hosts"
# Host patterns taken verbatim from the 44 tenants in upstream edpevent_se.py.
CANDIDATES="
https://edpmobile.danderyd.se/FutureWeb/SimpleWastePickup
https://futureweb.danderyd.se/FutureWeb/SimpleWastePickup
https://futureweb.danderyd.se/FutureWebBasic/SimpleWastePickup
https://edpfuture.danderyd.se/EDPFutureWeb/SimpleWastePickup
https://kundportal.danderyd.se/FutureWeb/SimpleWastePickup
https://minasidor.danderyd.se/FutureWeb/SimpleWastePickup
https://edpmypage.danderyd.se/FutureWebOS/SimpleWastePickup
https://services.danderyd.se/FutureWeb/SimpleWastePickup
https://edpfuture.verdis.se/EDPFutureWeb/SimpleWastePickup
https://futureweb.verdis.se/FutureWebBasic/SimpleWastePickup
"
LIVE=""
for base in $CANDIDATES; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 -A "$UA" \
         -X POST "$base/SearchAdress?searchText=Karlsro" 2>/dev/null)
  printf '    %-64s %s\n' "$base" "${code:-000}"
  case "$code" in 200|204|400|405) LIVE="${LIVE} $base" ;; esac
done
hr

if [ -n "${LIVE// /}" ]; then
  echo "==> 4. live SearchAdress against the host(s) that answered"
  for base in $LIVE; do
    echo "--- $base"
    curl -sS --max-time 20 -A "$UA" -X POST "$base/SearchAdress?searchText=Karlsro" | head -c 1200
    echo
  done
  hr
fi

echo "==> VERDICT"
case "$FOUND" in
  edpevent)
    cat <<'MSG'
    Danderyd runs EDP FutureWeb, which upstream ALREADY supports.

    DO NOT write a new source module. Two things follow:

    1. You can use it today, with no code at all:

         waste_collection_schedule:
           sources:
             - name: edpevent_se
               args:
                 street_address: "YOUR ADDRESS"
                 url: "<the SimpleWastePickup URL printed above>"

    2. The upstream contribution shrinks to a four-line entry in
       SERVICE_PROVIDERS in edpevent_se.py, plus its doc page row:

         "danderyd": {
             "title": "Danderyds kommun",
             "url": "https://www.danderyd.se",
             "api_url": "<the SimpleWastePickup URL printed above>",
         },

       Add a TEST_CASES entry using service_provider: danderyd.
       research/danderyd_se.draft.py should then be deleted, not finished.
MSG
    ;;
  avfallsapp)
    echo "    Danderyd runs Avfallsappen (Nova) — upstream supports this as"
    echo "    avfallsapp_se. Add a provider entry there instead of a new module."
    ;;
  ics)
    echo "    Possible ICS feed. If it is a real subscribable calendar, this becomes"
    echo "    a ~20-line YAML file in upstream doc/ics/yaml/ and no Python at all."
    ;;
  *)
    cat <<'MSG'
    No known shared platform matched.

    That is NOT yet proof a new module is needed — the widget may load its
    endpoint dynamically, or sit in an iframe this script did not follow.
    Confirm with the DevTools capture in research/CAPTURE.md before writing
    any code, and check the request URLs against upstream's shared platforms.

    Only if that also comes back negative is research/danderyd_se.draft.py
    the right thing to finish.
MSG
    ;;
esac
echo
echo "    raw capture kept in $OUT/"
