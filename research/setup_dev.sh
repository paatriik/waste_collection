#!/usr/bin/env bash
# Bootstrap a test rig and verify the Danderyd patch against upstream.
#
#   bash research/setup_dev.sh [WORKDIR]
#
# Idempotent. Default WORKDIR is $SCRATCH/wcs if SCRATCH is set, else ./.devrig.
# Clones upstream, builds a venv, works around the stdlib-shadowing problem,
# applies patches/0001-edpevent_se-add-danderyd.patch and runs upstream's CI gate.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-${SCRATCH:-$REPO/.devrig}}"
UPSTREAM="$WORK/upstream"
VENV="$WORK/venv"
PKGROOT="$WORK/pkgroot"
PATCH="$REPO/patches/0001-edpevent_se-add-danderyd.patch"

INNER="$UPSTREAM/custom_components/waste_collection_schedule/waste_collection_schedule"
SRC="$INNER/source/edpevent_se.py"

mkdir -p "$WORK"

echo "==> upstream checkout"
if [ -d "$UPSTREAM/.git" ]; then
  echo "    already present at $UPSTREAM"
else
  git clone --depth 1 https://github.com/mampfes/hacs_waste_collection_schedule.git "$UPSTREAM"
fi

echo "==> venv"
[ -d "$VENV" ] || python3 -m venv "$VENV"
# homeassistant is deliberately omitted: it is ~200 MB, pins Python >= 3.12, and
# the structural test suite does not import it. Only the live HA layer needs it.
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q \
  requests beautifulsoup4 lxml python-dateutil pyyaml pytz \
  jinja2 icalendar icalevents DateTime pycryptodome typing_extensions \
  pypdf pdfminer.six curl_cffi pytest ruff

echo "==> package root"
# The HA integration layer contains calendar.py, which shadows the stdlib
# `calendar` module if you put custom_components/waste_collection_schedule on
# PYTHONPATH. Expose only the inner library package instead.
rm -rf "$PKGROOT" && mkdir -p "$PKGROOT"
ln -sfn "$INNER" "$PKGROOT/waste_collection_schedule"

echo "==> apply patch"
git -C "$UPSTREAM" checkout -- \
  custom_components/waste_collection_schedule/waste_collection_schedule/source/edpevent_se.py \
  doc/source/edpevent_se.md
git -C "$UPSTREAM" apply "$PATCH"
echo "    applied $(basename "$PATCH")"

echo "==> upstream CI gate"
( cd "$UPSTREAM" && "$VENV/bin/python" -m pytest tests/test_source_components.py -q )

echo "==> lint (repo's own ruff.toml)"
( cd "$UPSTREAM" && "$VENV/bin/ruff" check "$SRC" && "$VENV/bin/ruff" format --check "$SRC" )

echo "==> live fetch (needs network access to future.danderyd.se)"
( cd "$INNER/test" && PYTHONPATH="$PKGROOT" "$VENV/bin/python" test_sources.py \
    -s edpevent_se -l --icon --sorted 2>&1 | grep -A8 -i danderyd ) || \
  echo "    live fetch unavailable — check egress to future.danderyd.se"

cat <<EOF

Ready.

  WORK      $WORK
  python    $VENV/bin/python
  upstream  $UPSTREAM  (patch applied, diff is exactly 2 files)

Re-run the live test on its own:

  cd $INNER/test && PYTHONPATH=$PKGROOT $VENV/bin/python test_sources.py -s edpevent_se -l --icon

Confirm the diff is clean before submitting:

  git -C $UPSTREAM diff --name-only
EOF
