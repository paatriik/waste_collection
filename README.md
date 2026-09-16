# Danderyd waste-collection source — handoff

Staging repo for adding **Danderyds kommun** (Stockholm, Sweden) to
[mampfes/hacs_waste_collection_schedule](https://github.com/mampfes/hacs_waste_collection_schedule).

This README is written for whoever picks the work up next, including a fresh Claude
session with no memory of it. Read it top to bottom before doing anything.

---

## START HERE

```bash
# 1. Is the network blocker gone? This is the only thing that decides what you do next.
curl -sS -o /dev/null -w '%{http_code}\n' https://www.danderyd.se/

# 2. If and only if that printed 200 — this is the decisive step. Nothing else
#    is worth doing until it has produced a verdict.
bash research/probe_platform.sh 'Karlsrovägen 4'

# 3. Build the test rig (~7 min first run, idempotent, safe to re-run).
bash research/setup_dev.sh

# 4. Read the investigation log. Newest entry last.
cat research/NOTES.md
```

Step 1 prints `200` → go to **Path A**. It prints `000` → go to **Path B**.

`probe_platform.sh` decides the route: **EDP FutureWeb** and **Avfallsappen/Nova**
are one dict entry in an existing upstream module, **ICS** is one yaml and no Python,
and only **NO MATCH** justifies the new module drafted here. It has never returned
anything but `INCONCLUSIVE`, because the network has never been open.

---

## Current state

| | |
|---|---|
| Goal | Danderyd supported upstream. **Which files change is not yet decided** — see `probe_platform.sh` |
| Upstream base | `release/3.0.0`, **not** `master` |
| Blocked on | The collection widget's HTTP endpoints, which are still unknown |
| Source module | Draft at `research/danderyd_se.draft.py`. Two methods unimplemented. Only needed if the probe says NO MATCH |
| Doc page | `doc/source/danderyd_se.md` — essentially final, same caveat |
| Upstream CI gate | **Passes** on release/3.0.0: `pytest -m "not live"` → 8000 passed, 8 skipped, 2355 deselected; `tests/test_source_components.py` → 42 passed; ruff clean |
| Live fetch test | Never run. Cannot run until the endpoints are known |

The CI-gate pass is trustworthy: a negative control (`COUNTRY = "sw"`) makes the suite
fail with `unsupported country code 'sw' in source danderyd_se`, so it really is
validating this file rather than skipping it. Re-run that control if you ever doubt a
green result — `setup_dev.sh` prints the exact command.

Note the pass count is identical with and without the Danderyd files installed. That is
expected: the source tests iterate every source inside a fixed set of test functions
rather than parametrising per source. The negative control, not the count, is what
proves the file is being read.

---

## The blocker

The cloud environment runs at **Trusted** network access — package registries, GitHub
and cloud SDKs only. Requests to `danderyd.se` are refused by the egress proxy:

```
kind:   connect_rejected
detail: gateway answered 403 to CONNECT (policy denial or upstream failure)
host:   www.danderyd.se:443
```

`example.com` and `google.com` are refused too, so it is the allowlist, not the site.

**Do not retry this within a session that started blocked.** The allowlist is read when
the VM boots. A policy change cannot reach a running session; it needs a new one. If
`curl` returns `000`, that is the final answer for this session — say so and move to
Path B rather than burning turns on retries.

Diagnose with `curl -sS "$HTTPS_PROXY/__agentproxy/status"` — `recentRelayFailures`
names the host and reason. Never disable TLS verification or unset `HTTPS_PROXY`.

To fix it: claude.ai/code → cloud icon above the message box → hover the environment →
gear icon → **Network access: Custom** → **Allowed domains**:

```
danderyd.se
*.danderyd.se
verdis.se
*.verdis.se
```

Tick **Also include default list of common package managers**, save, start a new session.
([docs](https://code.claude.com/docs/en/cloud-environments#allow-specific-domains))

---

## Path A — network works

0. **Run `bash research/probe_platform.sh 'Karlsrovägen 4'` first.** If it returns
   EDP FutureWeb, Avfallsappen/Nova or ICS, stop — steps 1-7 below are the wrong
   route and the draft module is dead weight. Only `NO MATCH` leads here.
1. Fetch the calendar page and find the widget's JavaScript:
   `https://www.danderyd.se/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/nar-hamtas-mitt-avfall/`
   (also try the short form `https://www.danderyd.se/avfallsschema`).
   `research/capture.sh` automates the fetch-and-grep if useful.
2. Identify two endpoints: the **address autocomplete** fired while typing, and the
   **schedule** call fired after selecting an address. Note what identifier the second
   one takes — a raw address string, or an opaque id returned by the first.
3. Implement `_search_address` and `_fetch_schedule` in the draft. Leave the rest alone;
   `fetch()`, the icon map and the error handling are already correct.
4. Confirm the waste-type strings verbatim and reconcile them with `ICON_MAP`. Keys are
   lower-cased and whitespace-collapsed, so only wording matters, not casing.
5. Move the file to
   `custom_components/waste_collection_schedule/waste_collection_schedule/source/danderyd_se.py`
   and delete the draft docstring.
6. Re-run `bash research/setup_dev.sh` (it picks up the final path automatically), then
   the live test — the script prints the exact command.
7. Iterate until the test case returns non-empty collections.

## Path B — network still blocked

The endpoints have to come from a machine that can reach the site. `research/CAPTURE.md`
has three options for the user; the DevTools one takes about two minutes and is the most
reliable. Ask for it, then implement from what comes back — Path A steps 3-7 do not
themselves need network until step 6.

Do not stall waiting. There is no useful offline work left beyond this point; the
remaining unknowns are all on the wire.

---

## Facts already established — do not re-derive these

- **Danderyd is not supported upstream.** `git grep -ril danderyd` over the whole
  upstream tree returns zero hits on `master` **and** on `release/3.0.0` (re-checked
  2026-09-16). It is not in `edpevent_se.py`, `avfallsapp_se.py`, `recollect.yaml` or any
  other shared-platform config. That means Danderyd has to be *added* somewhere — it does
  **not** by itself mean a new module. If the backend turns out to be EDP or Avfallsappen,
  the correct change is one dict entry in the existing module, not a new file.
- **Verdis AB** is the collection contractor, and also serves **Täby, Järfälla and
  Simrishamn**. If those share a calendar backend, one module could cover four
  municipalities via `EXTRA_INFO` — worth 30 seconds checking once the backend is known.
- **Verdis "Mina sidor" is a dead end.** It requires a login, and upstream refuses
  login-gated sources outright. Only the public address search on danderyd.se is viable.
- **Waste streams.** Villa/radhus standard subscription is *matavfall* + *restavfall*.
  Optional add-ons: *trädgårdsavfall*, *returpapper* (6 or 13 pickups/year). From 2026
  food-waste sorting is mandatory and kerbside packaging ("Närsortera") joins the
  standard subscription: paper and plastic every second week, glass and metal every
  fourth. Also collected, probably on request rather than on a calendar: *grovavfall*,
  *farligt avfall*, *elavfall*, *fallfrukt*, *slam*.
- **The calendar is periodically regenerated**, and the page says when it was last
  refreshed. Subscription changes made after that date do not appear until the next
  refresh. This is a data-freshness caveat for users, not a bug to work around. It also
  hints the backend may serve a static dataset rather than query a live system — still
  fine upstream, as long as the module fetches it at runtime.
- **Test address.** Probe and live-test with `Karlsrovägen 4, 18253 Danderyd`. That is
  the contributor's home address, so it must **never** reach `TEST_CASES` or the doc
  page — both now carry the literal placeholder `<TEST_ADDRESS>`, which has to be swapped
  for a confirmed public, non-residential address (the kommunhus is the obvious
  candidate) before anything is submitted. Upstream runs `TEST_CASES` against the live
  endpoint, so the replacement must be verified to resolve, not guessed. These files are
  public and permanent.

---

## Upstream rules that will bite you

From upstream `CLAUDE.md` and `doc/contributing_source.md`, re-verified against
`release/3.0.0` on 2026-09-16 (none of those four contributing docs has changed since;
last touch was 2026-09-14):

- A PR contains **only** the source module and its doc page. `README.md`, `info.md`,
  `sources.json`, `source_metadata.json` and `translations/*.json` are generated by CI
  post-merge. Including them fails review. Never run `update_docu_links.py` in a branch.
- `doc/source/<module>.md` is **not** generated. Write it by hand. It is a common miss.
- No hardcoded schedules. Fetch live on every `fetch()`.
- No login-required endpoints.
- `ICON_MAP` values must be `Icons` enum members, not raw `"mdi:…"` strings. Do not
  extend the enum in a source PR.
- `PARAM_TRANSLATIONS`, `PARAM_DESCRIPTIONS` and `HOW_TO_GET_ARGUMENTS_DESCRIPTION` may
  only use the keys `en`, `de`, `fr`, `it`, `nl` (`nl` is new on release/3.0.0 —
  `waste_types.py:26`, `field_terms.py:31`). **Swedish is not allowed** and fails CI.
  Providing only `en` is fine.
- **`doc/source/edpevent_se.md` must never be hand-edited.** Its provider list sits inside
  a `<!--Begin of service section-->` block that upstream regenerates after merge. Same
  for any other multi-provider doc page.
- **ICS route:** the key for extra providers in `doc/ics/yaml/` is `regions:`, not
  `extra_info:` (14 yamls use `regions:`, 0 still use `extra_info:`).
- Raise the typed exceptions from `waste_collection_schedule.exceptions`. Never a bare
  `Exception`, and never `return []` on error.
- `COUNTRY = "se"`.
- `SOURCE_CODEOWNERS = ["@paatriik"]` — strongly encouraged, and already set.

## Submitting

Upstream takes PRs only from a fork; this repo cannot open one. When the source is
working:

1. Fork `mampfes/hacs_waste_collection_schedule` to the user's account.
2. Branch off **`release/3.0.0`** (never commit to the fork's default branch). New-source
   work is based on and PR'd against the 3.0.0 line, not `master`.
3. Copy in the files the probe's verdict calls for — paths here mirror upstream exactly.
   New legacy source = exactly two files (module + `doc/source/<module>.md`). EDP or
   Avfallsappen = one existing `.py`, nothing else. ICS = one yaml, nothing else.
4. Verify the diff contains nothing else:
   `git diff $(git merge-base upstream/release/3.0.0 HEAD)..HEAD --name-only`
5. PR against `mampfes/hacs_waste_collection_schedule:release/3.0.0`.

---

## Dev rig notes

`research/setup_dev.sh` handles all of this; the notes are here for when it breaks.

- **`homeassistant` IS required** on `release/3.0.0`, despite being ~200 MB. The branch
  added `tests/conftest.py` (absent on `master`) with a bare `import homeassistant`, to
  pin HA's `voluptuous` → `probatio` swap ahead of collection (#7415). Without it the
  whole suite dies at collection with `ModuleNotFoundError`. The old advice to omit it
  was correct for `master` only.
- **Python ≥ 3.12 is required.** `parsers.py:47` uses PEP 695 `type Response = ...`,
  a `SyntaxError` on 3.11. Upstream CI runs 3.12 + `homeassistant==2024.4.0` ("minimum"
  lane) and 3.14 + latest ("current" lane); the script mirrors the minimum lane.
- **The real gate is `pytest -m "not live"`, not one file.** `pytest.ini` carries an
  explicit `python_files` allowlist of 15 test files and the workflow runs the lot
  (~5m40s, 8000 tests). `tests/test_source_components.py` alone is 42 tests and ~2s —
  useful for iteration, but it is not what CI runs.
- **`calendar.py` shadows the stdlib.** Putting
  `custom_components/waste_collection_schedule` on `PYTHONPATH` makes the HA layer's
  `calendar.py` shadow the standard library's `calendar`, and `import requests` then dies
  deep inside `email.utils`. Expose only the inner `waste_collection_schedule` package —
  the script symlinks it into a clean `pkgroot/`.
- **`pytest -k danderyd` deselects everything.** The tests iterate over all sources
  internally rather than parametrising. Run the whole file; it takes ~2 seconds.

## Files

| Path | |
|---|---|
| `research/danderyd_se.draft.py` | The source module. Two methods left to implement |
| `doc/source/danderyd_se.md` | User-facing doc page, required by upstream |
| `research/NOTES.md` | Investigation log and progress entries |
| `research/CAPTURE.md` | Three ways to obtain the endpoints |
| `research/capture.sh` | Automates the static half of the capture |
| `research/probe_platform.sh` | **Decides the route.** EDP / Avfallsappen / ICS / NO MATCH. Never yet run with network |
| `research/setup_dev.sh` | Builds the test rig (release/3.0.0, py≥3.12) and runs the CI gate |

`custom_components/.../source/danderyd_se.py` does not exist yet — that path is the
finished article's home, and `setup_dev.sh` prefers it over the draft once it appears.

## Done means

`probe_platform.sh` has returned a real verdict, the change matches that verdict, a live
fetch returns non-empty collections with sensible Swedish waste types and future dates,
`pytest -m "not live"` passes with zero failures, ruff is clean, and the diff contains
nothing but the files that verdict calls for.
