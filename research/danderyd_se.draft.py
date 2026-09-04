"""DRAFT — not shippable yet, and possibly not needed at all.

STOP before finishing this. Run `bash research/probe_platform.sh` from a machine
with network access first. Danderyd may be served by EDP FutureWeb, which upstream
already supports through the multi-tenant `edpevent_se` module — that module takes
a free-form `url` argument, so Danderyd's absence from its SERVICE_PROVIDERS list
says nothing about whether it works. If the probe reports EDP (or Avfallsappen, or
an ICS feed), delete this file: the contribution is then a few lines in an existing
module, and writing a new one for an already-covered provider is upstream's most
common rejection reason. See "The platform question" in README.md.

Only if the probe rules all of those out: everything here except the two methods
marked TODO is settled and does not depend on the widget's wire format. Fill in
`_search_address` and `_fetch_schedule` from the capture (see CAPTURE.md), move
this file to
custom_components/waste_collection_schedule/waste_collection_schedule/source/danderyd_se.py
and drop this docstring.
"""

import re
from datetime import date, datetime

import requests
from waste_collection_schedule import Collection, Icons
from waste_collection_schedule.exceptions import (
    SourceArgumentNotFound,
    SourceArgumentNotFoundWithSuggestions,
)

TITLE = "Danderyds kommun"
DESCRIPTION = "Source for Danderyds kommun household waste collection, Sweden."
URL = "https://www.danderyd.se"
COUNTRY = "se"

SOURCE_CODEOWNERS = ["@paatriik"]

# PROVISIONAL — must be replaced with a verified address before submitting.
# The value has to be an address the calendar actually resolves, in exactly the
# format the widget shows, and upstream's test_sources.py runs against it. Neither
# the format nor the resolvability can be confirmed without the endpoint capture,
# so treat this entry as a placeholder, not a decision. Use a civic address; a
# contributor's own street must not appear here, since these files are public and
# permanent and SOURCE_CODEOWNERS already names the contributor.
TEST_CASES: dict[str, dict] = {
    "Kommunhuset": {"street_address": "Djursholms Slott"},
}

# Waste streams Danderyd collects at villa/radhus, per the municipality's own pages.
# From 2026 food-waste sorting is mandatory and packaging is collected kerbside
# ("Närsortera"): paper and plastic fortnightly, glass and metal every fourth week.
# Keys are lower-cased and stripped before lookup, so the API's exact casing does
# not matter — but the wording does, and must be confirmed against a live response.
ICON_MAP = {
    "matavfall": Icons.BIO_KITCHEN,
    "restavfall": Icons.GENERAL_WASTE,
    "mat- och restavfall": Icons.GENERAL_WASTE,
    "trädgårdsavfall": Icons.GARDEN,
    "fallfrukt": Icons.GARDEN,
    "returpapper": Icons.PAPER,
    "tidningar och returpapper": Icons.PAPER,
    "pappersförpackningar": Icons.PAPER,
    "plastförpackningar": Icons.PLASTIC_PACKAGING,
    "papper- och plastförpackningar": Icons.PAPER,
    "glasförpackningar": Icons.GLASS,
    "metallförpackningar": Icons.METAL,
    "glas- och metallförpackningar": Icons.GLASS,
    "förpackningar": Icons.RECYCLING,
    "grovavfall": Icons.BULKY,
    "farligt avfall": Icons.HAZARDOUS,
    "elavfall": Icons.ELECTRONICS,
    "julgran": Icons.CHRISTMAS_TREE,
}

HOW_TO_GET_ARGUMENTS_DESCRIPTION = {
    "en": (
        "Open danderyd.se/avfallsschema, type your street into the address box and "
        "pick your address from the suggestions. Enter it here exactly as the "
        "calendar shows it. If no suggestion appears, try adding or removing the "
        "space between the street name and the house number — the calendar matches "
        "the address as plain text."
    ),
}

PARAM_TRANSLATIONS = {
    "en": {"street_address": "Street address"},
}

PARAM_DESCRIPTIONS = {
    "en": {
        "street_address": "Street address as listed in the Danderyd collection calendar."
    },
}


def _normalise(text: str) -> str:
    """Collapse whitespace and case so ICON_MAP lookups tolerate API formatting."""
    return re.sub(r"\s+", " ", text).strip().lower()


def _parse_date(value: str) -> date:
    """Accept the date formats Swedish municipal APIs commonly emit."""
    value = value.strip()
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    # ISO 8601 with a trailing Z, which strptime will not take directly.
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError as err:
        raise ValueError(
            f"Unrecognised date format from danderyd.se: {value!r}"
        ) from err


class Source:
    def __init__(self, street_address: str):
        self._street_address = street_address.strip()

    # -- TODO: wire up once the capture confirms the endpoints -------------------
    def _search_address(self, session: requests.Session) -> tuple[str, list[str]]:
        """Resolve the configured address to whatever id the schedule call needs.

        Returns (identifier, all_candidate_labels). The candidate list feeds
        SourceArgumentNotFoundWithSuggestions so a user who mistypes gets told
        what the calendar actually knows about.
        """
        raise NotImplementedError("endpoint unknown — see research/CAPTURE.md")

    def _fetch_schedule(self, session: requests.Session, identifier: str) -> list[dict]:
        """Return the collection records for a resolved address.

        Contract with fetch(): each record is a dict carrying at least

            "date"       -- a string _parse_date accepts
            "waste_type" -- the Swedish label, verbatim from the API

        The API almost certainly uses different key names. Normalise them here so
        fetch() stays independent of the wire format.
        """
        raise NotImplementedError("endpoint unknown — see research/CAPTURE.md")

    # -- settled ----------------------------------------------------------------
    def fetch(self) -> list[Collection]:
        session = requests.Session()
        session.headers.update(
            {
                "User-Agent": "Mozilla/5.0 (compatible; home-assistant-waste-collection-schedule)",
                "Accept": "application/json",
            }
        )

        identifier, candidates = self._search_address(session)
        if not identifier:
            if candidates:
                raise SourceArgumentNotFoundWithSuggestions(
                    "street_address", self._street_address, candidates
                )
            raise SourceArgumentNotFound("street_address", self._street_address)

        entries: list[Collection] = []
        for record in self._fetch_schedule(session, identifier):
            waste_type = record["waste_type"].strip()
            entries.append(
                Collection(
                    date=_parse_date(record["date"]),
                    t=waste_type,
                    icon=ICON_MAP.get(_normalise(waste_type)),
                )
            )

        # No raise on an empty result. _search_address has already raised if the
        # address is unknown, so reaching this point means it resolved. Danderyd
        # regenerates the calendar periodically, and a property can legitimately
        # have no dates listed in between. Raising SourceArgumentNotFound here
        # would tell the user to check their spelling, which is both wrong and
        # unactionable. Upstream's rule bans swallowing *errors*, not empty data.
        return entries
