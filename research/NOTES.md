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

### 2026-09-16 — third session, still blocked, and now we know why

Checked the blocker the way the README prescribes. Result is unchanged, but this session
produced a diagnosis rather than another "still 403":

| Check | Result |
|---|---|
| `curl https://www.danderyd.se/` | `000` (proxy answered 403 to CONNECT) |
| `curl https://www.verdis.se/` | `000` |
| `curl https://example.com/` | `000` — so it is the allowlist, not the site |
| Container uptime at the time of the check | **2 minutes** — this was a genuinely fresh VM, so the "policy changes need a new session" caveat does not explain it |
| `WebFetch` on the calendar page | `EGRESS_BLOCKED` — the managed fetch tool uses the same egress policy, so it is not a way around it |
| `WebSearch` | works (runs server-side, not from the container). Returns prose summaries only — no raw HTML or JS, so it cannot recover the endpoints |
| GitHub / pypi | reachable, as expected at Trusted |

**Root cause.** `list_environments` returns two environments, *both named "Default"*:

| environment_id | description |
|---|---|
| `env_014N2WDVgp9cGRukMu5QKUWc` | `Default - trusted network access` ← this session runs here |
| `env_01HF1jS5RigdyCyNN3krM8vc` | (none) |

Neither carries a custom allowlist, and the one this session uses still says *trusted*.
So the network setting was never applied to the environment these sessions actually boot
in — most likely edited on the other "Default" row, or not saved. Confirm the environment
id in the settings pane matches `env_014N2WDVgp9cGRukMu5QKUWc` before saving.

### Rig re-verified on a clean container

`bash research/setup_dev.sh` from scratch: exit 0, **42 passed** (upstream has grown from
35 since 2026-09-04), `ruff check` clean, `ruff format --check` clean. Nothing has rotted.

`grep -ril danderyd` over a fresh upstream clone still returns only the two files this
script copies in, so Danderyd is still unsupported upstream and a new module is still the
right shape. `grep -ril verdis` returns nothing.

One correction to an earlier note: **Simrishamn is not a Verdis municipality.** Upstream's
`doc/source/okrab_se.md` shows Simrishamn is served by ÖKRAB. The shared-backend idea is
therefore limited to Täby and Järfälla, not four municipalities.
