# Investigation notes — Danderyds kommun

## Outcome

**Danderyd runs EDP Futureweb (`SimpleWastePickup`), which upstream already supports
generically via `edpevent_se.py`.** No new source module is needed. The contribution is
a `SERVICE_PROVIDERS` entry, two `TEST_CASES`, ten `ICON_MAP` keys and a doc update —
see `patches/0001-edpevent_se-add-danderyd.patch`.

The earlier plan in this repo (a standalone `danderyd_se.py` module) was wrong. It was
built without network access, from the municipality's prose description of the widget,
and it assumed a bespoke backend. The draft and its doc page have been deleted.

## How the platform was identified

The calendar page

<https://www.danderyd.se/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/nar-hamtas-mitt-avfall/>

carries no widget JavaScript of its own. It embeds an iframe:

```html
<iframe src="https://future.danderyd.se/Danderyd/EDPFutureweb/SimpleWastePickup/SimpleWastePickup"
        width="300" height="150">
```

That iframe loads `Assets/JavascriptComponents/SimpleWastePickup.js`, a jQuery UI
autocomplete whose two calls are the standard EDP Futureweb pair.

The earlier `grep -ri danderyd` over upstream returned zero hits, which was true but
misleading: `edpevent_se.py` is keyed on *service provider*, not municipality, and
Danderyd was simply not yet listed. Checking for the platform, not the place name, is
what found it.

## The API

Base: `https://future.danderyd.se/Danderyd/EDPFutureweb/SimpleWastePickup`

### 1. Address search

```
POST {base}/SearchAdress?searchText=Skolvägen+1
```

The widget sends a JSON body; upstream sends the term as a query parameter with an empty
body. Both work. Note `requests` sets `Content-Length: 0` on an empty POST — `curl -X POST -G`
does not, and the server answers `411 Length Required`. That is a curl artifact, not a
difference the module has to handle.

```json
{"Succeeded": true,
 "Buildings": ["Skolvägen 1, Enebyberg (201642)", "Skolvägen 2, Enebyberg (204982)"]}
```

The building id in parentheses is part of the string that step 2 expects.

### 2. Schedule

```
GET {base}/GetWastePickupSchedule?address=Skolvägen+1,+Enebyberg+(201642)
```

```json
{"RhServices": [
  {"WasteType": "Papper/Plast",
   "NextWastePickup": "2026-09-28",
   "WastePickupFrequency": "Måndag jämn vecka ",
   "WastePickupsPerYear": 26,
   "BinType": {"Code": "KÄ240", "Size": 240.0, "Unit": "l", "ContainerType": "Kärl tvådelat"},
   "IsActive": true, "BuildingID": "201642", "Fee": {...}}
]}
```

No API key, no cookie, no CSRF token, no `Referer` check, no login. Dates are `%Y-%m-%d`,
which `edpevent_se.py` already parses.

## Waste types returned

Surveyed 77 addresses across 15 Danderyd streets (248 service records):

| WasteType | n | Icon mapped to | Already upstream? |
|---|---|---|---|
| `Restavfall` | 76 | `GENERAL_WASTE` | yes |
| `Matavfall` | 68 | `BIO_KITCHEN` | yes |
| `Papper/Plast` | 42 | `RECYCLING` | **added** |
| `Returpapper` | 12 | `NEWSPAPER` | **added** |
| `Metall` | 8 | `METAL` | **added** |
| `Glas/Glas/Metal` | 7 | `RECYCLING` | **added** |
| `Färgat Glas` | 7 | `GLASS_COLORED` | **added** |
| `Ofärgat glas` | 7 | `GLASS` | **added** |
| `Papper` | 5 | `PAPER` | **added** |
| `Trädgårdsavfall` | 5 | `GARDEN` | yes |
| `Plast` | 4 | `PLASTIC_PACKAGING` | **added** |
| `Elektronik` | 4 | `ELECTRONICS` | **added** |
| `Grovavfall` | 3 | `BULKY` | **added** |

`ICON_MAP` lookup in `edpevent_se.py` is an exact, case-sensitive `dict.get`, so the
inconsistent casing upstream of it (`Färgat Glas` vs `Ofärgat glas`) has to be mirrored
verbatim. `Papper/Plast` and `Glas/Glas/Metal` are multi-compartment bins carrying
several streams at once, so they get the generic `RECYCLING` rather than the icon of
whichever stream happens to be named first.

The additions are purely additive — every existing key keeps its value — so other
EDPEvent providers can only gain icons where they previously fell back to `mdi:help`.

### Records with no date

16 of 248 records had an empty `NextWastePickup`. `edpevent_se.py` skips those (with a
warning) unless the frequency parses as a week number. That is existing upstream
behaviour for inactive or on-request services and is out of scope here.

## Test cases

| Case | Streams exercised |
|---|---|
| `Skolvägen 1, Enebyberg` | Restavfall, Matavfall, Trädgårdsavfall, Papper/Plast, Glas/Glas/Metal |
| `Klingsta Gård` | Restavfall, Matavfall, Grovavfall, Metall, Färgat Glas, Ofärgat glas |

Between them they cover 9 of the 13 observed waste types and every icon added by this
patch except `Returpapper`, `Papper`, `Plast` and `Elektronik`. Both search strings
resolve to the intended building as `Buildings[0]`, which is what upstream's `fetch()`
takes. Neither is a contributor's home address.

## Verification

Against upstream master `8b21f6a` (2026-09-16):

| Check | Result |
|---|---|
| `pytest tests/test_source_components.py` | 42 passed |
| Negative control (raw `"mdi:bottle-wine"` in a new `ICON_MAP` entry) | fails `test_icon_map_uses_canonical_icons` — the suite really does validate these entries |
| `ruff check` / `ruff format --check` (repo's own `ruff.toml`) | clean |
| Live `test_sources.py -s edpevent_se -l --icon` | 5 and 6 entries for the two Danderyd cases, correct dates, no `mdi:help` |
| `git diff --name-only` | exactly 2 files, no generated files |

Reproduce all of it with `bash research/setup_dev.sh`.

Note: ruff must be run with the repo's own `ruff.toml`, not a hand-rolled
`--select E,F,W,I`. The repo ignores `E203,E501,E721`; overriding that reports four
pre-existing long lines in `edpevent_se.py` that CI does not care about.

## Not verified

Verdis AB also collects for **Täby, Järfälla and Simrishamn**. If those run EDP Futureweb
too, each is a further four-line `SERVICE_PROVIDERS` entry. This session's egress
allowlist covers `danderyd.se` only, so `taby.se`, `jarfalla.se` and `simrishamn.se` were
refused by the proxy and the hypothesis is untested. Worth ten minutes on a machine with
open network access; do not add a provider entry without a live fetch behind it.

## Upstream rules that apply

- The diff must be exactly the source module and its doc page. `README.md`, `info.md`,
  `sources.json`, `source_metadata.json` and `translations/*.json` are generated by CI
  post-merge. Never run `update_docu_links.py` in a branch.
- `doc/source/edpevent_se.md` is hand-maintained **in full**. Its
  `<!--Begin of service section-->` markers look generated, but `START_SERVICE_SECTION`
  and `END_SERVICE_SECTION` in `update_docu_links.py` are defined and never used —
  dead constants. Same for the country-section markers. The list must be edited by hand,
  and it is alphabetical.
- `EXTRA_INFO` is derived from `SERVICE_PROVIDERS` by a comprehension, so a new provider
  needs no separate `EXTRA_INFO` edit.
- `ICON_MAP` values must be `Icons` enum members. Do not extend the enum in a source PR.
- Upstream takes PRs only from a fork. See the README for the submission steps.
