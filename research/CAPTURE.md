# How to capture the endpoints

Pick **one** of the three. A is least work for you; C is the most reliable.

---

## A. Open up this session's network access (preferred — then I do the rest)

The cloud environment this session runs in is set to **Trusted** network access, which
allows package registries, GitHub and cloud SDKs and nothing else. That is why every
request to `danderyd.se` returns a proxy 403.

1. Go to <https://claude.ai/code> → environment settings for the environment this session uses.
2. Set **Network access** to **Custom**.
3. In **Allowed domains**, add:
   ```
   *.danderyd.se
   danderyd.se
   *.verdis.se
   verdis.se
   ```
4. Tick **Also include default list of common package managers** (otherwise pip/GitHub break).
5. Save, then start a new session on this branch.

Caveat: the allowlist is read when the VM starts, so an already-running session may not
pick it up. Assume a new session is needed.

Reference: <https://code.claude.com/docs/en/cloud-environments#allow-specific-domains>

---

## B. Run the capture script

On any machine that can reach the site:

```bash
bash research/capture.sh
```

Paste back `danderyd-capture/urls_interesting.txt` and `danderyd-capture/api_paths.txt`.

This only fetches the public pages and their JavaScript. It sends no address, stores no
cookies, and uploads nothing. It finds the endpoints if they are written literally into
the page's JavaScript, which is the common case. If the bundle is heavily minified or the
widget is a third-party iframe, fall back to C.

---

## C. Browser DevTools (the reliable one, ~2 minutes)

1. Open <https://www.danderyd.se/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/nar-hamtas-mitt-avfall/>
   in Chrome or Edge.
2. `F12` → **Network** tab → filter **Fetch/XHR** → tick **Preserve log**.
3. Clear the log, then type `Karlsrovägen` into the address box and wait for the
   autocomplete list.
4. Click a `Karlsrovägen` entry so the collection dates render.
5. You now have two or three requests in the list. For **each** of them:
   - right-click → **Copy** → **Copy as cURL**, and paste it back to me;
   - click the request → **Response** tab → copy the JSON body, and paste that back too.

What I specifically need out of it:

| Question | Where to look |
|---|---|
| Autocomplete URL + query parameter name | the request fired while typing |
| What the autocomplete returns (plain strings? objects with an id?) | its Response tab |
| Schedule URL + what identifier it takes | the request fired after clicking |
| The schedule JSON, including the Swedish waste-type labels and date format | its Response tab |
| Any `X-Api-Key`, `Authorization`, `Cookie` or CSRF header | the cURL command |

If you would rather not paste raw cURL: **right-click anywhere in the Network list →
Save all as HAR with sensitive data**, and send the `.har`. It contains everything above
in one file.

### Before you send it

A HAR or cURL dump contains whatever you typed and whatever cookies the site set. Use
the public street `Karlsrovägen` with no house number, and do the capture in a private /
incognito window so there is nothing personal in the file.

---

## Before you implement anything from the capture

Look at the request URLs you captured **first**, and compare them against the shared
platforms upstream already supports. `research/probe_platform.sh` does this automatically,
but by eye:

| If a captured URL looks like… | Then |
|---|---|
| `…/FutureWeb…/SimpleWastePickup/SearchAdress` | It is **EDP FutureWeb**. Upstream `edpevent_se` already handles it — no new module. Use it with `url:` set to the `…/SimpleWastePickup` base, and contribute a `SERVICE_PROVIDERS` entry. |
| `…avfallsapp.se/…/nova/v1/…` | It is **Avfallsappen**. Upstream `avfallsapp_se` handles it — add a provider entry. |
| ends in `.ics` / `webcal:` | A YAML entry in upstream `doc/ics/yaml/`. No Python. |

Only if none of these match is `research/danderyd_se.draft.py` the right thing to finish.
Writing a new module for a provider upstream already covers is the single most common
reason these PRs get rejected (upstream's own mistake #5).

## Also worth checking while you are on the page

- Is there a **"Prenumerera"**, **"iCal"**, **".ics"** or **"Lägg till i kalender"** link
  anywhere in the calendar widget? If yes, say so — an ICS feed means this becomes a
  ~20-line YAML file in upstream's `doc/ics/yaml/` instead of a Python module, which is a
  much smaller and much more maintainable contribution.
- Does the widget offer a **"beställ hämtningsschema"** / PDF download? Note the URL if so.
- Which waste types are listed for a typical villa: *Mat- och restavfall*, *Trädgårdsavfall*,
  *Returpapper*, *Förpackningar*? Exact Swedish spelling matters — those strings become the
  sensor names and the `ICON_MAP` keys.
