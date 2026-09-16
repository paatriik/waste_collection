#!/usr/bin/env python3
"""Add Danderyd as an EDPEvent tenant in an upstream checkout.

Use this ONLY if research/probe_platform.sh (or a DevTools capture) shows Danderyd
served by EDP FutureWeb. The whole upstream contribution is then two entries in
edpevent_se.py -- the provider list in doc/source/edpevent_se.md sits inside a
<!--Begin of service section--> block that upstream's CI generates after merge, so
it must NOT be hand-edited, and update_docu_links.py must not be run in a branch.

    python3 research/add_edp_provider.py \
        --api-url https://HOST/FutureWeb/SimpleWastePickup \
        --test-address "SOME CIVIC ADDRESS 1"
"""
import argparse
import pathlib
import sys

PROVIDER_KEY = "danderyd"
TITLE = "Danderyds kommun"
SITE = "https://www.danderyd.se"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-url", required=True)
    ap.add_argument("--test-address", required=True)
    ap.add_argument(
        "--repo",
        default=".devrig/upstream",
        help="path to the upstream checkout",
    )
    a = ap.parse_args()

    if "SimpleWastePickup" not in a.api_url:
        print(
            f"refusing: {a.api_url!r} does not look like a FutureWeb "
            "SimpleWastePickup base URL",
            file=sys.stderr,
        )
        return 2

    src = (
        pathlib.Path(a.repo)
        / "custom_components/waste_collection_schedule/waste_collection_schedule"
        / "source/edpevent_se.py"
    )
    text = src.read_text()

    if f'"{PROVIDER_KEY}"' in text:
        print(f"{PROVIDER_KEY} already present — nothing to do")
        return 0

    provider = (
        f'    "{PROVIDER_KEY}": {{\n'
        f'        "title": "{TITLE}",\n'
        f'        "url": "{SITE}",\n'
        f'        "api_url": "{a.api_url}",\n'
        f"    }},\n"
    )
    test_case = (
        f'    "Danderyd - {TITLE}": {{\n'
        f'        "street_address": "{a.test_address}",\n'
        f'        "service_provider": "{PROVIDER_KEY}",\n'
        f"    }},\n"
    )

    # Anchor on the closing brace of each dict, identified by what follows it.
    for anchor, addition, what in (
        ('}\n\nEXTRA_INFO = [', provider, "SERVICE_PROVIDERS"),
        ('}\n\nCOUNTRY = "se"', test_case, "TEST_CASES"),
    ):
        if text.count(anchor) != 1:
            print(
                f"refusing: expected exactly one {what} anchor, "
                f"found {text.count(anchor)} — upstream layout changed",
                file=sys.stderr,
            )
            return 3
        text = text.replace(anchor, addition + anchor, 1)

    src.write_text(text)
    print(f"added {PROVIDER_KEY} to SERVICE_PROVIDERS and TEST_CASES in {src}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
