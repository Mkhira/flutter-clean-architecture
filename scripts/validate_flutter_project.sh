#!/usr/bin/env bash
#
# validate_flutter_project.sh
#
# Non-interactive validation for a Flutter project. Run from the project root.
# It runs pub get, optionally build_runner (only when needed), format, analyze,
# and tests. It never deletes source files.
#
# Usage:
#   scripts/validate_flutter_project.sh [--codegen] [--skip-tests]
#
set -euo pipefail

CODEGEN=0
SKIP_TESTS=0

usage() {
  cat <<'EOF'
validate_flutter_project.sh — validate a Flutter project (non-interactive)

USAGE:
  validate_flutter_project.sh [--codegen] [--skip-tests] [--help]

OPTIONS:
  --codegen      Force-run build_runner (dart run build_runner build
                 --delete-conflicting-outputs). If omitted, build_runner runs
                 only when generated-code inputs are detected under lib/.
  --skip-tests   Do not run flutter test even if test/ exists.
  --help         Show this help and exit.

STEPS (in order):
  1. flutter pub get
  2. build_runner            (only if --codegen or generated inputs detected)
  3. dart format .
  4. flutter analyze
  5. check_layers            (domain purity + presentation→data; only if
                              check_layers.sh + lib/)
  6. flavor config           (fails if build.gradle references a missing
                              flavorizr.gradle.kts; no-op when no flavors)
  7. flutter test            (only if test/ exists and not --skip-tests)

The script exits non-zero on the first failing step. It is non-destructive:
build_runner uses --delete-conflicting-outputs only for generated outputs, never
source files.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --codegen) CODEGEN=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "Error: unknown argument '$arg'" >&2
      echo "Run with --help for usage." >&2
      exit 2
      ;;
  esac
done

# --- Preconditions ---------------------------------------------------------

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: 'flutter' was not found on PATH. Install Flutter first." >&2
  exit 1
fi

if [ ! -f "pubspec.yaml" ]; then
  echo "Error: pubspec.yaml not found. Run this script from the Flutter project root." >&2
  exit 1
fi

if ! grep -q "flutter" pubspec.yaml; then
  echo "Error: pubspec.yaml does not reference Flutter; this does not look like a Flutter project." >&2
  exit 1
fi

# --- Quiet-on-success step runner ------------------------------------------
# Each step's stdout+stderr go to a per-step /tmp log; on success print exactly
# one line ("✓ <label>"), on failure print the last 30 log lines and exit with
# the step's own code. Commands, flags, ordering and exit semantics are
# unchanged — only output handling is.
run_step() {
  local label="$1"; shift
  local log; log="$(mktemp)"
  if "$@" >"$log" 2>&1; then
    echo "✓ $label"
    rm -f "$log"
  else
    local rc=$?
    echo "✗ $label — last 30 log lines:" >&2
    tail -30 "$log" >&2
    exit "$rc"
  fi
}

# --- Detect generated-code inputs -----------------------------------------

needs_codegen() {
  # Returns 0 (true) if any generated-code input markers are present under lib/.
  [ -d "lib" ] || return 1
  grep -R -l -E \
    "part '.*\.g\.dart';|part '.*\.freezed\.dart';|@JsonSerializable|@RestApi|@Envied|@freezed|@Freezed|@riverpod" \
    lib >/dev/null 2>&1
}

# --- Flavor config integrity ----------------------------------------------
# Flavorizr's `android:buildGradle` injects `apply(from = "flavorizr.gradle.kts")`
# into the Android build script, but it is `android:flavorizrGradle` that WRITES
# that file. If a flavorizr.yaml lists only `android:buildGradle`, the build
# script references a file that never gets created and the Android build fails —
# something `flutter analyze` and unit tests never exercise. This cheap check
# catches the dangling reference deterministically (no native build required).
check_flavor_config() {
  local referenced=0 f
  for f in "android/app/build.gradle.kts" "android/app/build.gradle"; do
    if [ -f "$f" ] && grep -q "flavorizr\.gradle" "$f"; then
      referenced=1
    fi
  done
  [ "$referenced" -eq 1 ] || return 0   # no flavorizr reference → nothing to verify

  if [ -f "android/app/flavorizr.gradle.kts" ] || [ -f "android/app/flavorizr.gradle" ]; then
    return 0
  fi

  echo "android/app/build.gradle references flavorizr.gradle but the file is missing." >&2
  echo "Flavorizr's 'android:buildGradle' only injects the apply(...) line; it is" >&2
  echo "'android:flavorizrGradle' that writes android/app/flavorizr.gradle.kts." >&2
  echo "Fix: add 'android:flavorizrGradle' to flavorizr.yaml instructions and re-run" >&2
  echo "flavorizr, or author android/app/flavorizr.gradle.kts by hand (see" >&2
  echo "references/env-and-flavors.md, flavorizr gotcha #3)." >&2
  return 1
}

# --- Run steps -------------------------------------------------------------

run_step "pub get" flutter pub get

RUN_CODEGEN=0
if [ "$CODEGEN" -eq 1 ]; then
  RUN_CODEGEN=1
elif needs_codegen; then
  echo "==> Generated-code inputs detected under lib/; build_runner will run."
  RUN_CODEGEN=1
else
  echo "==> No generated-code inputs detected; skipping build_runner."
fi

if [ "$RUN_CODEGEN" -eq 1 ]; then
  run_step "build_runner" dart run build_runner build --delete-conflicting-outputs
fi

run_step "dart format" dart format .

run_step "analyze" flutter analyze

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$SCRIPT_DIR/check_layers.sh" ] && [ -d "lib" ]; then
  run_step "check_layers" "$SCRIPT_DIR/check_layers.sh" lib
fi

run_step "flavor config" check_flavor_config

if [ -d "test" ] && [ "$SKIP_TESTS" -eq 0 ]; then
  run_step "flutter test" flutter test -r compact
else
  if [ "$SKIP_TESTS" -eq 1 ]; then
    echo "==> Skipping tests (--skip-tests)."
  else
    echo "==> No test/ directory; skipping tests."
  fi
fi

echo "==> Validation completed successfully."
