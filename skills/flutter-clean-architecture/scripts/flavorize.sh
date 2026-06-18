#!/usr/bin/env bash
#
# flavorize.sh — run flutter_flavorizr non-interactively and fix the three
# documented gotchas in one step (see references/env-and-flavors.md). Without
# this, each new flavorized project hand-repeats them and the FIRST native
# build breaks in ways `flutter analyze`/unit tests never catch.
#
# Usage (run from, or pass, the Flutter project root):
#   scripts/flavorize.sh [project_root]
#
# Requires a flavorizr.yaml at the project root (org/app-name/bundleIds are
# project-specific — author it first; the skill restricts `instructions:` to the
# native + flutter:flavors processors so hand-written entrypoints survive).
#
# It then:
#   1. runs `dart run flutter_flavorizr -f`   (no TTY prompt → no crash)
#   2. creates per-flavor iOS AppIcon-<flavor> sets by copying the default
#      (gotcha #1: xcconfigs reference AppIcon-$(ASSET_PREFIX) that never exist)
#   3. asserts android/app/flavorizr.gradle.kts was written and is referenced
#      (gotcha #3: android:buildGradle injects the apply() but it is
#       android:flavorizrGradle that WRITES the file)
#
set -euo pipefail

ROOT="${1:-.}"
die() { echo "error: $*" >&2; exit 1; }

[ -f "$ROOT/pubspec.yaml" ] || die "no pubspec.yaml in '$ROOT'"
[ -f "$ROOT/flavorizr.yaml" ] || \
  die "no flavorizr.yaml at project root — author it first (see env-and-flavors.md)"

echo "==> Running flutter_flavorizr (-f, non-interactive)"
( cd "$ROOT" && dart run flutter_flavorizr -f )

# --- gotcha #1: per-flavor iOS app-icon sets -------------------------------
ICONS="$ROOT/ios/Runner/Assets.xcassets"
if [ -d "$ICONS/AppIcon.appiconset" ]; then
  # Derive flavor names from flavorizr.yaml (the keys under `flavors:`).
  flavors=$(awk '
    /^flavors:/ {inflav=1; next}
    inflav && /^[a-zA-Z]/ {inflav=0}
    inflav && /^  [a-zA-Z0-9_]+:/ {gsub(/[: ]/,""); print}
  ' "$ROOT/flavorizr.yaml")
  for f in $flavors; do
    if [ ! -d "$ICONS/AppIcon-$f.appiconset" ]; then
      cp -R "$ICONS/AppIcon.appiconset" "$ICONS/AppIcon-$f.appiconset"
      echo "==> Created iOS AppIcon-$f.appiconset"
    fi
  done
else
  echo "==> (skip iOS icons: no AppIcon.appiconset — non-iOS project?)"
fi

# --- gotcha #3: Android gradle file must exist if referenced ----------------
referenced=0
for g in "$ROOT/android/app/build.gradle.kts" "$ROOT/android/app/build.gradle"; do
  [ -f "$g" ] && grep -q 'flavorizr\.gradle' "$g" && referenced=1
done
if [ "$referenced" -eq 1 ]; then
  if [ -f "$ROOT/android/app/flavorizr.gradle.kts" ] || \
     [ -f "$ROOT/android/app/flavorizr.gradle" ]; then
    echo "==> Android flavorizr.gradle present and referenced — OK"
  else
    die "build.gradle references flavorizr.gradle but the file is missing. Add 'android:flavorizrGradle' to flavorizr.yaml instructions and re-run (see env-and-flavors.md gotcha #3)."
  fi
fi

echo "==> Flavorization complete. Build a flavor with, e.g.:"
echo "      flutter run --flavor dev -t lib/main_dev.dart"
