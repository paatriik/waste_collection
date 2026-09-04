#!/usr/bin/env bash
# Bootstrap a working test rig for the Danderyd source.
#
#   bash research/setup_dev.sh [WORKDIR]
#
# Idempotent. Default WORKDIR is $SCRATCH/wcs if SCRATCH is set, else ./.devrig.
# Clones upstream, builds a venv, works around the stdlib-shadowing problem, copies
# this repo's draft source and doc page in, and runs upstream's CI gate.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-${SCRATCH:-$REPO/.devrig}}"
UPSTREAM="$WORK/upstream"
VENV="$WORK/venv"
PKGROOT="$WORK/pkgroot"

INNER="$UPSTREAM/custom_components/waste_collection_schedule/waste_collection_schedule"
SRC_DIR="$INNER/source"

mkdir -p "$WORK"

echo "==> upstream checkout"
if [ -d "$UPSTREAM/.git" ]; then
  echo "    already present at $UPSTREAM"
else
  git clone --depth 1 https://github.com/mampfes/hacs_waste_collection_schedule.git "$UPSTREAM"
fi

echo "==> venv"
[ -d "$VENV" ] || python3 -m venv "$VENV"
# homeassistant is deliberately omitted: it is ~200 MB and the structural test
# suite does not import it. Only the live HA integration layer needs it.
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

echo "==> install this repo's files into the checkout"
if [ -f "$REPO/custom_components/waste_collection_schedule/waste_collection_schedule/source/danderyd_se.py" ]; then
  cp "$REPO/custom_components/waste_collection_schedule/waste_collection_schedule/source/danderyd_se.py" "$SRC_DIR/danderyd_se.py"
  echo "    source: final"
else
  cp "$REPO/research/danderyd_se.draft.py" "$SRC_DIR/danderyd_se.py"
  echo "    source: DRAFT (endpoints not implemented)"
fi
cp "$REPO/doc/source/danderyd_se.md" "$UPSTREAM/doc/source/danderyd_se.md"

echo "==> upstream CI gate"
( cd "$UPSTREAM" && "$VENV/bin/python" -m pytest tests/test_source_components.py -q )

echo "==> lint"
"$VENV/bin/ruff" check --select E,F,W,I --line-length 88 --ignore E203,E501,E721 "$SRC_DIR/danderyd_se.py"
"$VENV/bin/ruff" format --check --line-length 88 "$SRC_DIR/danderyd_se.py"

cat <<EOF

Ready.

  WORK      $WORK
  python    $VENV/bin/python
  upstream  $UPSTREAM

Live fetch against TEST_CASES (needs network access to danderyd.se):

  cd $INNER/test && $VENV/bin/python test_sources.py -s danderyd_se -l

Import the module directly:

  PYTHONPATH=$PKGROOT $VENV/bin/python -c "from waste_collection_schedule.source import danderyd_se"
EOF
