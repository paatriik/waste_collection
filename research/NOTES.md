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

---

### 2026-09-16 — rebased onto release/3.0.0; network still blocked

**Network: still blocked. The probe never ran, so there is still no platform verdict.**

```
curl https://www.danderyd.se/   -> 000  (CONNECT tunnel failed, 403)
curl https://example.com/       -> 000
curl https://www.google.com/    -> 000
curl https://pypi.org/simple/   -> 200
curl https://github.com/        -> 400   (reachable; git works)
```

`$HTTPS_PROXY/__agentproxy/status` reports `selective: false` and
`recentRelayFailures` naming `www.danderyd.se:443`, `example.com:443`,
`www.google.com:443`, `www.verdis.se:443`, all `connect_rejected` /
"gateway answered 403 to CONNECT". So the environment is still at **Trusted**;
the allowlist change described in the README has not taken effect. It is read at
VM boot, so this cannot be resolved inside a running session.

#### Two referenced scripts did not exist

`research/probe_platform.sh` and `research/add_edp_provider.py` were referenced as
if present. Neither exists, and neither appears anywhere in this repo's history
(`git log --all --diff-filter=ADMR` over both names: no hits).

`research/probe_platform.sh` is now written (see below). `add_edp_provider.py` is
deliberately **not** written — it would automate a one-line edit that is only
knowable after the probe returns an `api_url`, and writing it now would bake in a
guess. Adding an EDP provider is a single dict entry (see "EDP contract" below).

#### Base branch moved to release/3.0.0

`.devrig/` is gitignored and the container is ephemeral, so `.devrig/upstream` did
not exist at session start — there was nothing tracking master to rebase. It is a
throwaway test rig, not where the work lives.

```
before:  (no checkout; fresh clone defaults to master)
after:   ## release/3.0.0...origin/release/3.0.0
         221295e6 Merge pull request #7415 from GreenDavidA/fix-ha-probatio-voluptuous-race
```

This staging repo's own branch (`claude/gifted-allen-rljfrz`) has no upstream
history in it — its three commits are its own — so there is nothing to rebase onto
release/3.0.0 either. The files here mirror upstream paths and get copied into the
checkout by `setup_dev.sh`; that is the only coupling.

#### Upstream facts re-verified on release/3.0.0

| Claim | Result |
|---|---|
| CLAUDE.md / CONTRIBUTING.md / doc/contributing_source.md / doc/contributing_ics.md changed since 2026-09-16 | **No.** Last touch 2026-09-14 (`5793dccf`). Same on master |
| Danderyd present upstream | **No.** `git grep -ril danderyd` on release/3.0.0: 0 hits |
| `edpevent_se.py` identical master vs release/3.0.0 | **Yes** |
| `avfallsapp_se.py` identical master vs release/3.0.0 | **Yes** |
| Language allowlist | **en, de, fr, it, nl** — `waste_types.py:26 SUPPORTED_LANGUAGES`, `field_terms.py:31 _LANGS`. `nl` is new vs. the old note in this file |
| ICS yaml key | **`regions:`** — 14 yaml files use it, **0** still use `extra_info:` |

#### The rig was broken against release/3.0.0 — two hard failures, both fixed

1. **`homeassistant` is now mandatory.** release/3.0.0 adds `tests/conftest.py`
   (absent on master), which does a bare `import homeassistant` to pin HA's
   `voluptuous` -> `probatio` swap ahead of collection (#7415). The old
   `setup_dev.sh` deliberately omitted it ("~200 MB, not needed") and now dies at
   collection with `ModuleNotFoundError: No module named 'homeassistant'`.
2. **Python >= 3.12 is now mandatory.** `parsers.py:47` uses PEP 695
   `type Response = ...`, a `SyntaxError` on 3.11. The venv was 3.11 and the whole
   suite failed to import. Upstream CI matrix is 3.12 + `homeassistant==2024.4.0`
   ("minimum" lane) and 3.14 + latest ("current" lane).

`setup_dev.sh` now clones `release/3.0.0`, picks the newest available
python >= 3.12, installs upstream's own `requirements.txt` plus
`ruff pytest freezegun homeassistant==2024.4.0 josepy<2` (mirroring the minimum
lane), and runs the real gate.

#### The real CI gate is far bigger than test_source_components.py

`pytest.ini` sets `addopts = -m "not live"` and an explicit `python_files`
allowlist of 15 test files. The workflow runs plain `pytest -m "not live"`, not a
single file. Measured on release/3.0.0, python 3.12, HA 2024.4.0:

| Run | Result |
|---|---|
| `pytest -m "not live"` — baseline, no Danderyd files | **8000 passed, 8 skipped, 2355 deselected** (5m38s) |
| `pytest -m "not live"` — with draft + doc installed | **8000 passed, 8 skipped, 2355 deselected** (5m36s) — identical |
| `pytest tests/test_source_components.py` | **42 passed** (matches the 42 seen on master) |
| `pytest test_source_components + test_doc_generation + test_doc_examples` | **312 passed** |
| `ruff check . --select E9,F63,F7,F82` (CI's own lint gate, whole repo) | clean |
| `ruff check --select E,F,W,I` on the source | clean |
| `ruff format --check` on the source | clean |
| Negative control `COUNTRY = "sw"` | **still bites** — `1 failed, 41 passed`, `unsupported country code 'sw' in source danderyd_se` |

The identical 8000 with and without the source is expected, not a red flag: the
source tests iterate all sources inside a fixed number of test functions rather
than parametrising per source. The negative control is what proves the file is
actually being validated, and it still does.

#### Home address removed from the two upstream-bound files

`TEST_CASES` held `"Karlsrovägen"` and the doc page's example held
`Karlsrovägen 1`. Both are the contributor's own street and both are now
`<TEST_ADDRESS>`, with a comment in the draft that it must be replaced by a
confirmed public non-residential address before submission. Research files
(`CAPTURE.md`, `probe_platform.sh` default) still name the street — they never go
upstream, and the probe has to be run against a real address to mean anything.

#### EDP contract, read off release/3.0.0 `edpevent_se.py`

Worth recording because it makes the probe decisive and the fix, if it matches,
a one-line change:

- `POST <api_url>/SearchAdress?searchText=<address>`
  -> `{"Succeeded": bool, "Buildings": ["<full address string>", ...]}`
- `GET <api_url>/GetWastePickupSchedule?address=<building>`
  -> `{"RhServices": [{"WasteType", "NextWastePickup", "WastePickupFrequency"}, ...]}`

`api_url` always ends `/SimpleWastePickup`, with the app segment varying:
`FutureWeb`, `FutureWebOS`, `FutureWebBasic`, `EDPFutureWeb`, `FutureWebVKFHus`.
Adding a municipality is one entry in `SERVICE_PROVIDERS` (`title`, `url`,
`api_url`); `EXTRA_INFO` is derived from it. `doc/source/edpevent_se.md` must not
be hand-edited.

Avfallsappen/Nova equivalent: `api_url` is
`https://<kommun>.avfallsapp.se/wp-json/nova/v1/` or `.../api/nova/v1/`. Note some
Nova providers need an `api_key` (device registration) — check whether Danderyd
would, since that is a worse user experience than EDP.

#### research/probe_platform.sh — written, but NEVER successfully run

It fetches the calendar pages plus `verdis.se`, follows referenced JS bundles,
counts EDP / Nova / ICS markers, then **actively** POSTs `/SearchAdress` against
every EDP base found in the assets plus guessed `danderyd.se` / `verdis.se`
deployments, and GETs the Nova address endpoint. It prints one of four verdicts:
EDP FutureWeb / Avfallsappen / ICS / NO MATCH.

Run here, it exits 2 at step 0 with
`VERDICT: INCONCLUSIVE — no egress to danderyd.se`, which is correct behaviour and
also the only thing it has ever printed. Its guessed host list is a guess; if it
returns NO MATCH, read `danderyd-probe/refs.txt` and `candidates.txt` before
believing it, because the widget may be an iframe from a host it did not try.

#### Still open

1. The platform verdict. Everything downstream depends on it and nothing can
   substitute for it.
2. A public, non-residential Danderyd address that the calendar actually resolves,
   for `TEST_CASES` and the doc example.
3. Whether Täby / Järfälla / Simrishamn share the backend — if EDP, they may be
   free additions in the same dict.

#### configuration.yaml, ready per verdict

Cannot be finalised without the probe, because the `name:` and the argument names differ
per route. Fill the placeholder the moment the verdict lands.

```yaml
# If EDP FutureWeb — <PROVIDER_KEY> is the new SERVICE_PROVIDERS key added to
# edpevent_se.py. Works immediately via `url:` even before that PR merges.
waste_collection_schedule:
  sources:
    - name: edpevent_se
      args:
        street_address: "Karlsrovägen 4"
        service_provider: <PROVIDER_KEY>
        # or, without waiting for the merge:
        # url: <API_URL ending in /SimpleWastePickup>

# If Avfallsappen / Nova
    - name: avfallsapp_se
      args:
        street_address: "Karlsrovägen 4"
        service_provider: <PROVIDER_KEY>
        # api_key: !secret avfallsapp_se_api_key   # only if the provider demands one

# If ICS
    - name: ics
      args:
        url: <ICS_OR_WEBCAL_URL>

# If NO MATCH — the module drafted here
    - name: danderyd_se
      args:
        street_address: "Karlsrovägen 4"
```

Note the live address above is fine in your own `configuration.yaml`; it is only
`TEST_CASES` and the doc page that must stay on `<TEST_ADDRESS>`.
