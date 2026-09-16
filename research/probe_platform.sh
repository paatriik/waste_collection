#!/usr/bin/env bash
# Decide which upstream route Danderyd belongs on, by looking at the wire.
#
#   bash research/probe_platform.sh [TEST_ADDRESS]
#
# NOTE: this script has never been executed against the live site. It was written
# offline, from the request/response contracts of the upstream sources it tests
# for (edpevent_se.py, avfallsapp_se.py on release/3.0.0). Treat its verdict as
# real evidence only once it has actually run and printed a response body.
#
# Needs egress to danderyd.se / verdis.se. Prints one of four verdicts:
#
#   EDP FutureWeb  -> add a SERVICE_PROVIDERS entry to upstream edpevent_se.py
#   Avfallsappen   -> add a SERVICE_PROVIDERS entry to upstream avfallsapp_se.py
#   ICS            -> add a yaml to upstream doc/ics/yaml/ (key `regions:`)
#   NO MATCH       -> a new legacy-style source module is required
#
# Sends the test address to the municipality's own public endpoints and nowhere
# else. Stores no cookies. Writes to ./danderyd-probe/.

set -u

ADDR="${1:-Karlsrovägen 4}"
OUT="danderyd-probe"
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
BASE="https://www.danderyd.se"

rm -rf "$OUT"; mkdir -p "$OUT/raw"

say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "------------------------------------------------------------"; }

get() { # url outfile -> prints "code size url"
  curl -sSL --compressed -A "$UA" -m 45 -o "$2" \
       -w '  %{http_code}  %{size_download}B  %{url_effective}\n' "$1" 2>&1
}

# ---------------------------------------------------------------- 0. reachability
hr; say "0. reachability"
code=$(curl -sS -o /dev/null -m 20 -w '%{http_code}' "$BASE/" 2>/dev/null)
say "  $BASE/ -> ${code:-000}"
if [ "${code:-000}" = "000" ]; then
  say
  say "VERDICT: INCONCLUSIVE — no egress to danderyd.se."
  say "The environment allowlist is read at VM boot, so this cannot be fixed"
  say "inside a running session. Start a new session with danderyd.se allowed."
  exit 2
fi

# ---------------------------------------------------------------- 1. pull pages
hr; say "1. pages"
i=0
for u in \
  "$BASE/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/nar-hamtas-mitt-avfall/" \
  "$BASE/avfallsschema" \
  "$BASE/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/avfallshamtning/" \
  "https://www.verdis.se/kommuner/danderyd/" ; do
  i=$((i+1)); get "$u" "$OUT/raw/page_$i.html"
done

# follow every script the pages reference, so platform markers inside bundles count
grep -ohiE '(src|href|data-[a-z-]+)="[^"]+"' "$OUT"/raw/*.html 2>/dev/null \
  | sed 's/^[^"]*"//; s/"$//' | sort -u > "$OUT/refs.txt"
i=0
grep -iE '\.js($|\?)' "$OUT/refs.txt" | sort -u | while IFS= read -r u; do
  case "$u" in
    //*) u="https:$u" ;; /*) u="$BASE$u" ;; http*) : ;; *) u="$BASE/$u" ;;
  esac
  i=$((i+1)); get "$u" "$OUT/raw/bundle_$i.js" >/dev/null 2>&1
done
say "  $(ls "$OUT"/raw 2>/dev/null | wc -l) file(s) fetched"

CORPUS=$(cat "$OUT"/raw/* 2>/dev/null)

# ---------------------------------------------------------------- 2. markers
hr; say "2. platform markers in fetched assets"

mark() { # label regex
  n=$(printf '%s' "$CORPUS" | grep -ciE "$2" 2>/dev/null || echo 0)
  printf '  %-26s %s\n' "$1" "$n"
}
mark "EDP FutureWeb"    'SimpleWastePickup|FutureWeb|SearchAdress|GetWastePickupSchedule|edpevent|edpmobile|edpfuture|edpmypage'
mark "Avfallsappen/Nova" 'avfallsapp\.se|wp-json/nova|/nova/v1'
mark "ICS / webcal"      'webcal://|\.ics([?"'"'"']|$)|ical'

printf '%s' "$CORPUS" | grep -ohaE 'https?://[A-Za-z0-9._-]+(:[0-9]+)?(/[A-Za-z0-9._~:/?#@!$&*+,;=%-]*)?' \
  | sed 's/[",);]*$//' | sort -u \
  | grep -iE 'futureweb|simplewastepickup|avfallsapp|nova|\.ics|webcal|verdis|edp' \
  > "$OUT/candidates.txt" 2>/dev/null
say "  candidate URLs -> $OUT/candidates.txt ($(wc -l < "$OUT/candidates.txt" 2>/dev/null || echo 0))"
sed 's/^/    /' "$OUT/candidates.txt" 2>/dev/null | head -25

# ---------------------------------------------------------------- 3. active EDP probe
hr; say "3. active EDP probe (POST /SearchAdress, address = $ADDR)"
say "   upstream contract: {\"Succeeded\":true,\"Buildings\":[\"<addr>\",...]}"

# every EDP base seen in the assets, plus the deployment patterns upstream already
# uses, applied to Danderyd's and Verdis' own hostnames.
{
  grep -oiE 'https?://[A-Za-z0-9._-]+/[A-Za-z0-9/_-]*(FutureWeb[A-Za-z]*|EDPFutureWeb)/SimpleWastePickup' "$OUT/candidates.txt" 2>/dev/null
  for host in edpmobile.danderyd.se futureweb.danderyd.se kundportal.danderyd.se \
              minasidor.danderyd.se edpfuture.verdis.se futureweb.verdis.se \
              kundportal.verdis.se minasidor.verdis.se edpmypage.verdis.se ; do
    for app in FutureWeb FutureWebOS FutureWebBasic EDPFutureWeb ; do
      printf 'https://%s/%s/SimpleWastePickup\n' "$host" "$app"
    done
  done
} | sort -u > "$OUT/edp_targets.txt"

EDP_HIT=""
while IFS= read -r base; do
  [ -n "$base" ] || continue
  body=$(curl -sS -m 20 -A "$UA" -X POST --data-urlencode "searchText=$ADDR" \
           "$base/SearchAdress" 2>/dev/null)
  code=$(curl -sS -o /dev/null -m 20 -A "$UA" -X POST --data-urlencode "searchText=$ADDR" \
           -w '%{http_code}' "$base/SearchAdress" 2>/dev/null)
  printf '  %-4s %s\n' "${code:-000}" "$base"
  case "$body" in
    *Buildings*|*Succeeded*)
      say "       ^^ EDP RESPONSE:"
      printf '%s\n' "$body" | head -c 1200 | sed 's/^/       /'
      say
      EDP_HIT="$base"
      printf '%s\n' "$body" > "$OUT/edp_searchadress.json"
      break ;;
  esac
done < "$OUT/edp_targets.txt"

# ---------------------------------------------------------------- 4. active Nova probe
NOVA_HIT=""
if [ -z "$EDP_HIT" ]; then
  hr; say "4. active Avfallsappen/Nova probe"
  for base in https://danderyd.avfallsapp.se/wp-json/nova/v1 \
              https://danderyd.avfallsapp.se/api/nova/v1 \
              https://verdis.avfallsapp.se/wp-json/nova/v1 ; do
    code=$(curl -sS -o "$OUT/raw/nova.json" -m 20 -A "$UA" \
             -w '%{http_code}' "$base/addresses?search=$(printf %s "$ADDR" | sed 's/ /%20/g')" 2>/dev/null)
    printf '  %-4s %s\n' "${code:-000}" "$base"
    case "${code:-000}" in
      2*) NOVA_HIT="$base"; sed 's/^/       /' "$OUT/raw/nova.json" | head -c 800; say; break ;;
    esac
  done
else
  hr; say "4. active Avfallsappen/Nova probe — skipped, EDP already matched"
fi

# ---------------------------------------------------------------- 5. ICS
hr; say "5. ICS / webcal feeds referenced"
printf '%s' "$CORPUS" | grep -ohaE '(webcal|https?)://[^"'"'"' <>]+\.ics[^"'"'"' <>]*' \
  | sort -u > "$OUT/ics.txt" 2>/dev/null
ICS_N=$(wc -l < "$OUT/ics.txt" 2>/dev/null || echo 0)
sed 's/^/  /' "$OUT/ics.txt" 2>/dev/null | head -10
say "  $ICS_N feed(s)"

# ---------------------------------------------------------------- verdict
hr
if [ -n "$EDP_HIT" ]; then
  say "VERDICT: EDP FutureWeb"
  say "  api_url: $EDP_HIT"
  say "  -> add a SERVICE_PROVIDERS entry to upstream edpevent_se.py."
  say "     Do NOT hand-edit doc/source/edpevent_se.md."
elif [ -n "$NOVA_HIT" ]; then
  say "VERDICT: Avfallsappen / Nova"
  say "  api_url: $NOVA_HIT"
  say "  -> add a SERVICE_PROVIDERS entry to upstream avfallsapp_se.py."
elif [ "${ICS_N:-0}" -gt 0 ]; then
  say "VERDICT: ICS feed"
  say "  -> add a yaml under upstream doc/ics/yaml/, using the \`regions:\` key."
else
  say "VERDICT: NO MATCH"
  say "  No EDP, Nova or ICS signature found."
  say "  -> finish research/danderyd_se.draft.py as a LEGACY-style source."
  say "  Next: open the calendar page in a browser with DevTools > Network,"
  say "  type the address, and read the two XHRs (see research/CAPTURE.md)."
  say "  Grep $OUT/refs.txt and $OUT/candidates.txt first — the widget may be"
  say "  an iframe from a host this script did not guess."
fi
hr
say "artifacts in ./$OUT/"
