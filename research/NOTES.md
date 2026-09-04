# Investigation notes — Danderyds kommun

## Target

- Municipality: **Danderyds kommun**, Stockholms län, Sweden (`COUNTRY = "se"`)
- Resident-facing lookup page:
  <https://www.danderyd.se/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/nar-hamtas-mitt-avfall/>
- Short URL also seen in search results: `danderyd.se/avfallsschema`
- Collection contractor: **Verdis AB** (<https://www.verdis.se/kommuner/danderyd/>).
  Verdis also runs Täby, Järfälla and Simrishamn — if the calendar backend is shared,
  one source module could cover several municipalities via `EXTRA_INFO`.
- Grease-separator sludge is collected by Ohlssons (out of scope — not household waste).

## Coverage check against upstream (done)

`grep -ri danderyd` over the whole upstream tree at master: **0 hits.**
Not covered by any existing module, and not present in any shared-platform config
(`edpevent_se.py`, `avfallsapp_se.py`, `recollect.yaml`, `mein_abfallkalender_online.yaml`, …).
Nearest Swedish modules are 19 `COUNTRY = "se"` sources, none in Stockholms län.

Conclusion: **a new source module is required.**

## What the widget does (from public descriptions, not yet verified against the wire)

1. Resident types a street address into a search box on the municipality page.
2. After a short delay, matching addresses appear as autocomplete options.
3. Resident clicks their address; a scrollable list of upcoming collection dates renders.
4. Guidance on the page: "if you don't find your address, try removing or adding spaces
   between letters and numbers" — suggests loose string matching against a fixed
   address table rather than a normalised address database.
5. The page carries a "calendar last updated <date>" notice and warns that subscription
   changes made after that date won't show. Danderyd changed waste system in June 2026.

Point 5 matters: it implies the calendar is generated from a **periodically refreshed
dataset**, possibly a static JSON blob served alongside the page, rather than a live
query against the billing system. That is still acceptable upstream — fetching a JSON
file over HTTP at runtime is a live fetch. What is *not* acceptable is embedding that
data in the source module.

## Blocker

This session's cloud environment runs at **Trusted** network access, whose allowlist
covers package registries, GitHub and cloud SDKs only. Every request to `danderyd.se`,
`verdis.se` (and `google.com`, `wikipedia.org`) is refused by the egress proxy:

```
kind:   connect_rejected
detail: gateway answered 403 to CONNECT (policy denial or upstream failure)
host:   www.danderyd.se:443
```

So the widget's endpoints cannot be discovered from inside this session. Either:

- **(A)** the environment's network access is switched to **Custom** with `*.danderyd.se`
  and `*.verdis.se` added (keeping the default package-manager list), or
- **(B)** the endpoints are captured on a machine that can reach the site — see
  `research/capture.sh` and `research/CAPTURE.md`.

## Open questions to resolve before implementing

1. Autocomplete endpoint: URL, method, query parameter name, response shape.
2. Schedule endpoint: URL, method, what identifier it takes (address string? an opaque
   building/customer id returned by the autocomplete step?), response shape.
3. Are there API keys, session cookies, CSRF tokens or `Referer` checks? Anything
   requiring a login disqualifies the source upstream.
4. Waste-type strings returned, verbatim in Swedish, so `ICON_MAP` can be built:
   expect some of *Mat- och restavfall*, *Matavfall*, *Restavfall*, *Trädgårdsavfall*,
   *Returpapper*, *Förpackningar* (papper/plast/glas/metall), *Grovavfall*.
5. Date format and how far ahead the feed runs.
6. Whether Täby / Järfälla / Simrishamn hit the same backend with a different tenant id.
7. Whether an iCal/`.ics` subscription exists. If it does, the far cheaper route is an
   entry in `doc/ics/yaml/` instead of a Python module.

---

## Progress log

### 2026-09-04 — offline groundwork complete

Verified against a local checkout of upstream master (draft source + doc page copied in,
inner package isolated on `PYTHONPATH` so `custom_components/.../calendar.py` does not
shadow the stdlib `calendar` module):

| Check | Result |
|---|---|
| `pytest tests/test_source_components.py` | **35 passed** |
| Negative control (`COUNTRY = "sw"`) | fails with `unsupported country code 'sw' in source danderyd_se` — confirms the suite really does validate this file rather than skipping it |
| `ruff check --select E,F,W,I` | clean |
| `ruff format --check` | clean |
| All 18 `ICON_MAP` values are `Icons` members | yes |
| Exception signatures match usage | `SourceArgumentNotFound(argument, value, …)`, `SourceArgumentNotFoundWithSuggestions(argument, value, suggestions)` |

So everything upstream's CI gate checks is already satisfied. What remains is the part
that needs the network: the two endpoint methods and a live `test_sources.py` run.

### Waste streams to expect (from the municipality's own pages)

Villa / radhus standard subscription: **matavfall** + **restavfall**. Optional add-ons:
**trädgårdsavfall**, **returpapper** (6 or 13 pickups/year). From 2026 food-waste sorting
is mandatory and kerbside packaging collection ("Närsortera") joins the standard
subscription — paper and plastic every second week, glass and metal every fourth week.
Also collected but likely on request rather than on a calendar: grovavfall, farligt
avfall, elavfall, fallfrukt, slam.

`ICON_MAP` is keyed on lower-cased, whitespace-collapsed strings, so only the wording
needs confirming against a live response, not the casing.

### Environment status

| Blocker | State |
|---|---|
| GitHub push | **resolved** — branch pushed |
| Network egress | **still blocked.** `example.com` and `google.com` are refused too, so the environment is still at `Trusted`. The allowlist is read at VM boot, so a policy change cannot take effect in an already-running session — a new session is required regardless |

### 2026-09-04 — handoff prepared

`research/setup_dev.sh` added and verified from a clean directory and from the default
path: clones upstream, builds the venv, works around the `calendar.py` shadowing, installs
this repo's files and runs the CI gate (35 passed) plus ruff. Exit 0 both times.

The live test command in the README was dry-run and behaves correctly — it resolves the
source, runs the `Karlsrovägen` case and stops at
`failed: endpoint unknown — see research/CAPTURE.md`. So the rig is sound end to end and
the only thing missing is the wire format.

Network at handoff: `https://www.danderyd.se/` still returns `000` (proxy 403).

### 2026-09-04 — second session: channel test, upstream re-check, draft fixes

**The blocker is confirmed across every available channel, not just `curl`.** The prior
session tested `curl` only. Retested:

| Channel | Result |
|---|---|
| `curl https://www.danderyd.se/` | `000` — proxy 403 on CONNECT |
| `WebFetch` (routes via Anthropic, not the container proxy) | `EGRESS_BLOCKED: Access to www.danderyd.se is blocked by the network egress proxy` |
| `WebSearch` | **works**, but returns prose summaries, not raw HTML or `<script>` URLs |
| `github.com` (git clone, GitHub MCP) | **works** |

So `WebSearch` and GitHub are usable and the rest is not. `WebSearch` cannot recover an
endpoint — it never returns the page source. Do not spend turns on it for that purpose.

**Open question 6 (shared Verdis backend) is largely answered, and the answer is no.**
Simrishamn *is* already supported upstream — as `okrab_se`, which posts to
`https://minasidor.okrab.se/MinaSidor_API/api/external/schedulePost/`. ÖKRAB
(Österlens Kommunala Renhållnings AB) is Simrishamn's own waste authority. Verdis is the
hauler there, not the calendar provider. **Verdis being the contractor therefore does not
imply a shared calendar backend**, and the "one module covers four municipalities" idea
loses most of its support. Täby and Järfälla are still unchecked, but the prior should now
be low. Neither appears anywhere upstream.

**No duplicate effort upstream.** `search_pull_requests` for danderyd/verdis/taby returns
0 results; no open issue requests Danderyd. There is no existing capture to reuse.

**Re-verified at upstream HEAD `1339b9b`** (not just the older checkout):

- `pytest tests/test_source_components.py` → 35 passed; `ruff check` and `ruff format` clean
- All 12 `Icons` members the draft uses exist in `icons.py`
- `Collection(icon=...)` is typed `str | None`, so an unmapped waste type passing `None` is fine
- `SourceArgumentNotFound(argument, value, message_addition=...)` and
  `SourceArgumentNotFoundWithSuggestions(argument, value, suggestions)` match the draft's usage
- Upstream's rules ban generic `Exception`; **nothing requires raising on an empty result**

**Three defects found and fixed in the draft:**

1. `TEST_CASES` used `Karlsrovägen` with no house number while
   `HOW_TO_GET_ARGUMENTS_DESCRIPTION` told users to include one — the module contradicted
   itself, and a bare street name would most likely not resolve in a live test. It was also
   the contributor's own street, which combined with `SOURCE_CODEOWNERS = ["@paatriik"]`
   links the codeowner to a specific street in a small municipality, permanently and
   publicly. Replaced with a civic placeholder and marked PROVISIONAL: the real value
   cannot be chosen before the capture, because the required address *format* is unknown.
   The doc page's example carried the same street and was changed too.
2. `fetch()` raised `SourceArgumentNotFound` when the schedule came back empty. Since
   `_search_address` already raises for an unknown address, an empty result means the
   address resolved but has no dates — which the municipality's own regeneration notice
   says is a real state. The old behaviour told the user to check their spelling, which is
   wrong and unactionable. Now returns the empty list.
3. `_fetch_schedule` had no stated contract, so the `record["date"]` / `record["waste_type"]`
   keys `fetch()` depends on were implicit. Documented in the docstring.

CI gate still green after all three (35 passed, ruff clean).

### 2026-09-04 — the premise was wrong: check the shared platforms first

Retested the network at the start of this pass: `danderyd.se`, `verdis.se` and
`example.com` all still `000`, `WebFetch` still `EGRESS_BLOCKED`. Environment unchanged.

**The conclusion "a new source module is required" was never established.** It rested on
`grep -ri danderyd` returning 0 hits upstream. That proves the *name* is absent; it does
not prove the *platform* is. `edpevent_se.py` is a multi-tenant module whose `Source`
takes a free-form `url` argument:

```python
def __init__(self, street_address, service_provider=None, url=None):
```

so it serves any `.../FutureWeb.../SimpleWastePickup` endpoint whether or not the kommun
appears in its `SERVICE_PROVIDERS` list. Absence from that list is not absence of support.
Upstream lists this exact error as common mistake **#5**: *"Provider already covered by a
shared platform. Check first."*

**EDP FutureWeb is now the leading hypothesis for Danderyd:**

- Upstream carries **44** FutureWeb tenants, two of them in Stockholm County — Nacka
  (`futureweb.nvoa.se/EDP/FutureWebBasic/SimpleWastePickup`) and Roslagsvatten
  (`edpmypage.roslagsvatten.se/FutureWebOS/SimpleWastePickup`).
- FutureWeb's flow is `POST {base}/SearchAdress?searchText=…` → addresses carrying a
  building id → `GetWastePickupSchedule`. That is exactly the type-then-pick behaviour
  described on danderyd.se, and exactly the two-step shape the draft assumes.
- Danderyd's "try adding or removing the space between letters and numbers" advice is the
  known FutureWeb address-matching quirk.
- Danderyd took billing over from Verdis in June 2026 and now invoices residents directly
  — the moment a kommun typically stands up a platform of this kind.

All circumstantial. `WebSearch` could not confirm or refute it (it returns prose, never
page source), and the site is unreachable. **It is a hypothesis, not a finding.**

`research/probe_platform.sh` added to settle it in one command from any networked machine:
fetches the calendar page and its JavaScript, fingerprints them against EDP FutureWeb,
Avfallsappen/Nova and ICS, probes ten candidate FutureWeb hostnames derived from the
naming patterns of the 44 existing tenants, runs a live `SearchAdress` against anything
that answers, and prints the verdict plus the exact YAML or `SERVICE_PROVIDERS` entry to
use. Verified: exits cleanly with a clear message when the network is blocked, and its
three detectors were unit-tested against synthetic fixtures for each platform (each fires
on its own fixture only, and extracts the right URL).

**Consequence if the probe comes back EDP:** `research/danderyd_se.draft.py` should be
*deleted*, not finished, and the contribution shrinks to a four-line `SERVICE_PROVIDERS`
entry plus a `TEST_CASES` row. The user could also configure `edpevent_se` with `url:`
and have this working in Home Assistant immediately, with no upstream PR at all.
