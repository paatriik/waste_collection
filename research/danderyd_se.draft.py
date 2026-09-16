"""DRAFT — not shippable yet.

Everything here except the two methods marked TODO is settled and does not depend
on the widget's wire format. When the endpoint capture arrives (see CAPTURE.md),
fill in `_search_address` and `_fetch_schedule`, move this file to
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

TEST_CASES: dict[str, dict] = {
    # Civic addresses only — never a contributor's home address. Upstream runs
    # these against the live endpoint, so <TEST_ADDRESS> must be replaced with a
    # real, public, non-residential address (e.g. the kommunhus) that has been
    # confirmed to resolve, before this is submitted.
    "<TEST_ADDRESS>": {"street_address": "<TEST_ADDRESS>"},
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
        "pick your address from the suggestions. Enter it here exactly as it is "
        "shown there, including the house number."
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
        """Return the raw collection records for a resolved address."""
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

        if not entries:
            raise SourceArgumentNotFound("street_address", self._street_address)

        return entries
