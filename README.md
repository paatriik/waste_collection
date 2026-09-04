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

# 2. Build the test rig (~1 min, idempotent, safe to re-run).
bash research/setup_dev.sh

# 3. Read the investigation log.
cat research/NOTES.md
```

Step 1 prints `200` → go to **Path A**. It prints `000` → go to **Path B**.

---

## Current state

| | |
|---|---|
| Goal | One new source module + one doc page, submitted as a PR to upstream `master` |
| Blocked on | The collection widget's HTTP endpoints, which are still unknown |
| Source module | Draft at `research/danderyd_se.draft.py`. Everything except two methods is done and verified |
| Doc page | `doc/source/danderyd_se.md` — essentially final |
| Upstream CI gate | **Passes.** `tests/test_source_components.py` → 35 passed, `ruff check` and `ruff format --check` clean |
| Live fetch test | Never run. Cannot run until the endpoints are known |

The CI-gate pass is trustworthy: a negative control (`COUNTRY = "sw"`) makes the suite
fail with `unsupported country code 'sw' in source danderyd_se`, so it really is
validating this file rather than skipping it. Re-run that control if you ever doubt a
green result.

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

- **Danderyd is not supported upstream.** `grep -ri danderyd` over the whole upstream
  tree at master returns zero hits. It is not in `edpevent_se.py`, `avfallsapp_se.py`,
  `recollect.yaml` or any other shared-platform config. A new source module is correct.
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
- **Test address.** The user lives on Karlsrovägen, 18253 Danderyd. Use `Karlsrovägen`
  **without a house number** in `TEST_CASES`, or a civic address such as the kommunhus.
  Upstream's own guidance is explicit that test cases must never carry a contributor's
  home address, and these files are public and permanent.

---

## Upstream rules that will bite you

From upstream `CLAUDE.md` and `doc/contributing_source.md`:

- A PR contains **only** the source module and its doc page. `README.md`, `info.md`,
  `sources.json`, `source_metadata.json` and `translations/*.json` are generated by CI
  post-merge. Including them fails review. Never run `update_docu_links.py` in a branch.
- `doc/source/<module>.md` is **not** generated. Write it by hand. It is a common miss.
- No hardcoded schedules. Fetch live on every `fetch()`.
- No login-required endpoints.
- `ICON_MAP` values must be `Icons` enum members, not raw `"mdi:…"` strings. Do not
  extend the enum in a source PR.
- `PARAM_TRANSLATIONS`, `PARAM_DESCRIPTIONS` and `HOW_TO_GET_ARGUMENTS_DESCRIPTION` may
  only use the keys `en`, `de`, `it`, `fr`. **Swedish is not allowed** and fails CI.
  Providing only `en` is fine.
- Raise the typed exceptions from `waste_collection_schedule.exceptions`. Never a bare
  `Exception`, and never `return []` on error.
- `COUNTRY = "se"`.
- `SOURCE_CODEOWNERS = ["@paatriik"]` — strongly encouraged, and already set.

## Submitting

Upstream takes PRs only from a fork; this repo cannot open one. When the source is
working:

1. Fork `mampfes/hacs_waste_collection_schedule` to the user's account.
2. Branch off `master` (never commit to the fork's `master`).
3. Copy in the two files — paths here mirror upstream exactly, so no rewriting.
4. Verify the diff contains nothing else:
   `git diff $(git merge-base upstream/master HEAD)..HEAD --name-only`
5. PR against `mampfes/hacs_waste_collection_schedule:master`, titled
   `Add source: Danderyds kommun (danderyd_se)`.

---

## Dev rig notes

`research/setup_dev.sh` handles all of this; the notes are here for when it breaks.

- **`homeassistant` is not needed** for the structural tests and is ~200 MB. The script
  omits it deliberately.
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
| `research/setup_dev.sh` | Builds the test rig and runs the CI gate |

`custom_components/.../source/danderyd_se.py` does not exist yet — that path is the
finished article's home, and `setup_dev.sh` prefers it over the draft once it appears.

## Done means

Live `test_sources.py -s danderyd_se -l` returns non-empty collections with sensible
Swedish waste types and dates, `tests/test_source_components.py` passes, ruff is clean,
and the diff is exactly two files.
