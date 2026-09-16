# Prompt for the next session

Fill in `<TEST_ADDRESS>` and paste the block below as the first message.
Start the session on repo `paatriik/waste_collection`, branch
`claude/waste-collection-hacs-integration-ujngt1`, in the cloud environment whose
network allowlist was opened on 2026-09-16.

---

```text
Continue the Danderyd waste-collection work on this branch. Read README.md and
research/NOTES.md first — every dead end is already recorded there, don't redo one.

Use this as the test address everywhere a civic address is needed:
<TEST_ADDRESS>

Do this in order:

1. Confirm network: curl -sS -o /dev/null -w '%{http_code}\n' https://www.danderyd.se/
   Expect 200. If it prints 000 you are in a session started before the allowlist
   change — say so and stop, because the allowlist is read at VM boot.

2. Run `bash research/probe_platform.sh`. This is the decisive step. Do not write
   or finish any source module before it has run. Show me its verdict.

3. Act on the verdict:
   - EDP FutureWeb -> run
       python3 research/add_edp_provider.py --api-url <URL the probe printed> \
         --test-address "<TEST_ADDRESS>"
     against the checkout .devrig/upstream, then run the CI gate. Delete
     research/danderyd_se.draft.py and doc/source/danderyd_se.md — they are not
     needed on this route. Also give me the configuration.yaml snippet so I can use
     it in Home Assistant straight away.
   - Avfallsappen/Nova -> add a provider entry to upstream avfallsapp_se.py instead.
   - An ICS feed -> a YAML entry in upstream doc/ics/yaml/. No Python at all.
   - No match -> only now finish research/danderyd_se.draft.py: implement
     _search_address and _fetch_schedule from what the probe captured, using the
     real Swedish waste-type strings for ICON_MAP.

4. Verify against real data before telling me it works:
   - bash research/setup_dev.sh  (CI gate + ruff; expect 42 passed, clean)
   - the live test the script prints, and it must return non-empty collections
     with sensible Swedish waste types and future dates.

Hard rules — these fail upstream review:
- doc/source/edpevent_se.md must NOT be hand-edited. Its provider list is inside a
  <!--Begin of service section--> block that upstream generates after merge.
- Never run update_docu_links.py in a branch. Never touch README.md, info.md,
  sources.json, source_metadata.json or translations/*.json — CI generates them.
- A new-source PR is exactly two files: the module and doc/source/<module>.md.
- No hardcoded schedules, no login-gated endpoints, no bare Exception — use the
  typed ones in waste_collection_schedule.exceptions. ICON_MAP values must be
  Icons enum members. PARAM_TRANSLATIONS etc. may only use en/de/it/fr keys;
  Swedish fails CI. COUNTRY = "se".
- Never put my own street in TEST_CASES or the doc page. Use <TEST_ADDRESS>.

Commit and push to this branch as you go. Do NOT open a pull request — upstream
only takes PRs from a fork, and I want to review before anything goes out.

Tell me plainly if something doesn't work rather than reporting success.
```
