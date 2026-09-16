#!/usr/bin/env bash
# Bootstrap a working test rig for the Danderyd source.
#
#   bash research/setup_dev.sh [WORKDIR]
#
# Idempotent. Default WORKDIR is $SCRATCH/wcs if SCRATCH is set, else ./.devrig.
# Clones upstream at release/3.0.0, builds a venv matching upstream's CI, copies
# this repo's draft source and doc page in, and runs upstream's real CI gate.
#
# Base branch is release/3.0.0, NOT master: upstream bases new-source work on the
# 3.0.0 line. Override with BRANCH=master if you need to compare.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-${SCRATCH:-$REPO/.devrig}}"
BRANCH="${BRANCH:-release/3.0.0}"
UPSTREAM="$WORK/upstream"
VENV="$WORK/venv312"
PKGROOT="$WORK/pkgroot"

INNER="$UPSTREAM/custom_components/waste_collection_schedule/waste_collection_schedule"
SRC_DIR="$INNER/source"

# release/3.0.0 uses PEP 695 `type X = ...` in parsers.py, which is a SyntaxError
# before 3.12. Upstream's CI matrix is 3.12 (minimum lane) and 3.14 (current).
PY=""
for c in python3.14 python3.13 python3.12; do
  command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }
done
if [ -z "$PY" ]; then
  echo "FATAL: need python >= 3.12 (release/3.0.0 uses PEP 695 syntax)." >&2
  exit 1
fi

mkdir -p "$WORK"

echo "==> upstream checkout ($BRANCH)"
if [ -d "$UPSTREAM/.git" ]; then
  echo "    already present at $UPSTREAM"
  git -C "$UPSTREAM" fetch --quiet origin "$BRANCH"
  git -C "$UPSTREAM" checkout --quiet "$BRANCH" 2>/dev/null \
    || git -C "$UPSTREAM" checkout --quiet -b "$BRANCH" "origin/$BRANCH"
else
  git clone --filter=blob:none --branch "$BRANCH" \
    https://github.com/mampfes/hacs_waste_collection_schedule.git "$UPSTREAM"
fi
echo "    $(git -C "$UPSTREAM" rev-parse --abbrev-ref HEAD) @ $(git -C "$UPSTREAM" rev-parse --short HEAD)"

echo "==> venv"
[ -d "$VENV" ] || "$PY" -m venv "$VENV"
echo "    $("$VENV/bin/python" -V)"
"$VENV/bin/pip" install -q --upgrade pip
# Mirrors upstream .github/workflows/validate.yaml, "minimum" lane.
# homeassistant is NOT optional any more: release/3.0.0 added tests/conftest.py,
# which imports it unconditionally to pin HA's voluptuous->probatio swap (#7415).
"$VENV/bin/pip" install -q ruff pytest freezegun \
  -r "$UPSTREAM/requirements.txt" "homeassistant==2024.4.0" "josepy<2"

echo "==> package root"
# The HA integration layer contains calendar.py, which shadows the stdlib
# `calendar` module if you put custom_components/waste_collection_schedule on
# PYTHONPATH. Expose only the inner library package instead.
rm -rf "$PKGROOT" && mkdir -p "$PKGROOT"
ln -sfn "$INNER" "$PKGROOT/waste_collection_schedule"

echo "==> install this repo's files into the checkout"
FINAL="$REPO/custom_components/waste_collection_schedule/waste_collection_schedule/source/danderyd_se.py"
if [ -f "$FINAL" ]; then
  cp "$FINAL" "$SRC_DIR/danderyd_se.py"
  echo "    source: final"
else
  cp "$REPO/research/danderyd_se.draft.py" "$SRC_DIR/danderyd_se.py"
  echo "    source: DRAFT (endpoints not implemented)"
fi
cp "$REPO/doc/source/danderyd_se.md" "$UPSTREAM/doc/source/danderyd_se.md"

echo "==> upstream CI gate"
( cd "$UPSTREAM" && "$VENV/bin/python" -c "from custom_components.waste_collection_schedule import config_flow" )
# The source-structure file alone (fast, ~2s) and then the full gating run.
( cd "$UPSTREAM" && "$VENV/bin/python" -m pytest tests/test_source_components.py -q )
if [ "${FULL:-1}" = "1" ]; then
  echo "==> full gate (pytest -m 'not live', ~6 min; FULL=0 to skip)"
  ( cd "$UPSTREAM" && "$VENV/bin/python" -m pytest -m "not live" -q | tail -3 )
fi

echo "==> lint"
( cd "$UPSTREAM" && "$VENV/bin/ruff" check . --select E9,F63,F7,F82 --output-format=concise )
"$VENV/bin/ruff" check --select E,F,W,I --line-length 88 --ignore E203,E501,E721 "$SRC_DIR/danderyd_se.py"
"$VENV/bin/ruff" format --check --line-length 88 "$SRC_DIR/danderyd_se.py"

cat <<EOF

Ready.

  WORK      $WORK
  branch    $BRANCH
  python    $VENV/bin/python
  upstream  $UPSTREAM

Live fetch against TEST_CASES (needs network access to danderyd.se):

  cd $INNER/test && $VENV/bin/python test_sources.py -s danderyd_se -l

Negative control — proves the gate really validates this file:

  sed -i 's/^COUNTRY = "se"/COUNTRY = "sw"/' $SRC_DIR/danderyd_se.py
  cd $UPSTREAM && $VENV/bin/python -m pytest tests/test_source_components.py -q
  # expect: 1 failed — unsupported country code 'sw' in source danderyd_se
EOF
