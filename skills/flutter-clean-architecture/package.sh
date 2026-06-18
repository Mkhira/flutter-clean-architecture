#!/usr/bin/env bash
#
# package.sh — build a distributable zip of this skill, excluding local cruft:
#   - macOS:   .DS_Store, __MACOSX
#   - Python:  __pycache__/, *.pyc
#   - Flutter: build/, .dart_tool/   (left behind if a flutter/xcode build ever
#              ran inside the skill dir — they are NOT part of the skill)
# Run from anywhere; the zip is written to the skill's PARENT directory so it
# never includes itself.
#
# ALWAYS use this instead of Finder's right-click "Compress" — Finder injects a
# __MACOSX/ tree that this script (and a plain `zip -x`) never produces.
#
# Usage: ./package.sh [version]     e.g.  ./package.sh V1  ->  <name>-V1.zip
#                                         ./package.sh      ->  <name>.zip
#
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="$(basename "$SELF_DIR")"
PARENT="$(cd "$SELF_DIR/.." && pwd)"
VER="${1:-}"
OUT="$NAME${VER:+-$VER}.zip"

# Scrub stray local/build artifacts before zipping.
find "$SELF_DIR" \( -name '__pycache__' -o -name '.DS_Store' -o -name '__MACOSX' \
  -o -name 'build' -o -name '.dart_tool' \) -exec rm -rf {} + 2>/dev/null || true
find "$SELF_DIR" -name '*.pyc' -delete 2>/dev/null || true

# Exclude the same patterns at zip time as belt-and-suspenders.
( cd "$PARENT" \
  && rm -f "$OUT" \
  && zip -r "$OUT" "$NAME" \
       -x "*.DS_Store" -x "*__pycache__*" -x "*.pyc" -x "*__MACOSX*" \
       -x "*/build/*" -x "*/.dart_tool/*" >/dev/null )

echo "✓ packaged: $PARENT/$OUT"
