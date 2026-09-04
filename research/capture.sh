#!/usr/bin/env bash
# Capture the Danderyd waste-calendar widget's static assets and any endpoint-looking
# strings inside them. Run this on a machine that can reach danderyd.se.
#
#   bash capture.sh
#
# Produces ./danderyd-capture/ and danderyd-capture.tgz. Nothing is uploaded anywhere.
# It sends no address and stores no cookies.

set -u

BASE="https://www.danderyd.se"
PAGES="
$BASE/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/nar-hamtas-mitt-avfall/
$BASE/avfallsschema
$BASE/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/avfallshamtning/
"
OUT="danderyd-capture"
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'

rm -rf "$OUT"; mkdir -p "$OUT/raw"

get() { # url outfile
  curl -sSL --compressed -A "$UA" -m 60 -o "$2" -w "  %{http_code}  %{size_download}B  %{url_effective}\n" "$1" 2>&1
}

abs() { # url  -> absolute
  case "$1" in
    //*)   printf 'https:%s\n' "$1" ;;
    /*)    printf '%s%s\n' "$BASE" "$1" ;;
    http*) printf '%s\n' "$1" ;;
    *)     printf '%s/%s\n' "$BASE" "$1" ;;
  esac
}

echo "== 1. pages =="
n=0
for u in $PAGES; do
  n=$((n+1))
  get "$u" "$OUT/raw/page_$n.html"
done

echo
echo "== 2. references in those pages =="
grep -ohiE '(src|href|action|data-[a-z-]+)="[^"]+"' "$OUT"/raw/*.html 2>/dev/null \
  | sed 's/^[^"]*"//; s/"$//' | sort -u > "$OUT/refs.txt"
echo "  $(wc -l < "$OUT/refs.txt") unique references -> refs.txt"

echo
echo "== 3. downloading javascript =="
grep -iE '\.js($|\?)' "$OUT/refs.txt" | sort -u > "$OUT/js_refs.txt"
n=0
while IFS= read -r u; do
  [ -n "$u" ] || continue
  n=$((n+1))
  get "$(abs "$u")" "$OUT/raw/bundle_$n.js"
done < "$OUT/js_refs.txt"
echo "  $n bundle(s)"

echo
echo "== 4. downloading json referenced from markup =="
grep -iE '\.json($|\?)' "$OUT/refs.txt" | sort -u > "$OUT/json_refs.txt"
n=0
while IFS= read -r u; do
  [ -n "$u" ] || continue
  n=$((n+1))
  get "$(abs "$u")" "$OUT/raw/data_$n.json"
done < "$OUT/json_refs.txt"
echo "  $n json file(s)"

echo
echo "== 5. absolute URLs found inside the bundles =="
grep -ohaE 'https?://[A-Za-z0-9._-]+(:[0-9]+)?(/[A-Za-z0-9._~:/?#@!$&*+,;=%-]*)?' \
  "$OUT"/raw/*.js "$OUT"/raw/*.html 2>/dev/null \
  | sed 's/[",);]*$//' | sort -u > "$OUT/urls_all.txt"
grep -viE 'w3\.org|schema\.org|googleapis|gstatic|jquery|bootstrap|fontawesome|mozilla\.org|github\.io|npmjs|purl\.org|xmlns' \
  "$OUT/urls_all.txt" > "$OUT/urls_interesting.txt"
sed 's/^/  /' "$OUT/urls_interesting.txt" | head -60

echo
echo "== 6. endpoint-looking path strings inside the bundles =="
grep -ohaE '"[/][A-Za-z0-9/_.{}$-]{3,120}"' "$OUT"/raw/*.js 2>/dev/null \
  | grep -iE 'api|search|sok|address|adress|tomning|hamtning|hämtning|calendar|kalender|schedule|pickup|waste|avfall|estate|fastighet|building|customer' \
  | sort -u > "$OUT/api_paths.txt"
sed 's/^/  /' "$OUT/api_paths.txt" | head -60
echo "  ($(wc -l < "$OUT/api_paths.txt") total -> api_paths.txt)"

echo
echo "== 7. iframes (widget may be hosted elsewhere) =="
grep -ohiE '<iframe[^>]*>' "$OUT"/raw/*.html 2>/dev/null | sed 's/^/  /' | head -20

echo
tar czf danderyd-capture.tgz "$OUT" 2>/dev/null
echo "done -> $OUT/ and danderyd-capture.tgz"
echo "Most useful files to paste back: urls_interesting.txt, api_paths.txt"
