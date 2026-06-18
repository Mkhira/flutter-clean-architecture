#!/usr/bin/env bash
#
# doctor.sh — preflight for a Flutter Clean Architecture project (and a drift
# check for the skill's own references).
#
# It surfaces the failures this skill cares about *before* they cost a build:
#   1. environment (Flutter / Dart present and which version)
#   2. dependency resolution — runs `flutter pub get`; on failure it points at
#      the codegen-conflict playbook (the json_annotation/json_serializable trap)
#   3. key-package freshness — current vs latest for the skill's stack, so you
#      see what's behind (resolution success is the real compatibility gate, so
#      this is advisory, not a hard rule — bloc_test/bloc majors legitimately
#      differ, etc.)
#   4. codegen inputs — reminds you to run build_runner if any are present
#   5. --docs: scans references/ for hardcoded version mentions to review
#
# Usage (from the Flutter project root):
#   scripts/doctor.sh [--docs]
#
# Exit code: non-zero only if `flutter pub get` fails (a real blocker).
#
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF_DIR="$(cd "$SELF_DIR/.." && pwd)/references"
DO_DOCS=0
for a in "$@"; do
  case "$a" in
    --docs) DO_DOCS=1 ;;
    -h|--help) echo "usage: scripts/doctor.sh [--docs]"; exit 0 ;;
    *) echo "error: unknown option '$a'" >&2; exit 2 ;;
  esac
done

FAIL=0

# --- 1. environment --------------------------------------------------------
echo "== Environment =="
if command -v flutter >/dev/null 2>&1; then
  flutter --version 2>/dev/null | head -1
else
  echo "✗ flutter not found on PATH."
  FAIL=1
fi
command -v dart >/dev/null 2>&1 && dart --version 2>&1 | head -1
# The generators emit Dart 3 language features (sealed classes, switch-expression
# patterns, final class), so an installed Dart below 3.0 can't compile scaffolds.
_ver_num() { printf '%s' "$1" | awk -F. '{printf "%d",($1*10000)+($2*100)+($3+0)}'; }
INST_DART="$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [ -n "$INST_DART" ] && [ "$(_ver_num "$INST_DART")" -lt "$(_ver_num 3.0.0)" ]; then
  echo "✗ Dart $INST_DART is below 3.0 — generated code (sealed classes, patterns) won't compile."
  FAIL=1
fi
echo

# --- project-scoped checks -------------------------------------------------
if [ -f pubspec.yaml ]; then
  # Advisory: does this project's declared min Dart allow the Dart 3 features the
  # generators emit? (Bumpable — not a hard fail like a missing/old installed SDK.)
  PROJ_DART="$(grep -E "^[[:space:]]+sdk:[[:space:]]*['\"]?[\^>= ]*[0-9]" pubspec.yaml 2>/dev/null \
    | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
  if [ -n "$PROJ_DART" ] && [ "$(_ver_num "$PROJ_DART")" -lt "$(_ver_num 3.0.0)" ]; then
    echo "⚠ pubspec 'environment: sdk:' min is $PROJ_DART; bump to '^3.0.0' so generated"
    echo "  features (sealed classes, patterns) compile."
    echo
  fi
  PUBGET_OK=0
  echo "== Dependency resolution (flutter pub get) =="
  if flutter pub get >/tmp/_doctor_pubget.log 2>&1; then
    echo "✓ resolved"
    PUBGET_OK=1
  else
    echo "✗ resolution FAILED — first errors:"
    grep -iE "because|incompatible|version solving failed|so,|requires" \
      /tmp/_doctor_pubget.log | head -12
    echo
    echo "  → Likely the codegen/test conflict. See references/package-stack.md"
    echo "    ('Common resolution conflict') and references/codegen-troubleshooting.md:"
    echo "    relax the leaf dep (e.g. json_annotation) to the band json_serializable"
    echo "    accepts — never hand-pin analyzer/test_api."
    FAIL=1
  fi
  echo

  if [ "$PUBGET_OK" -eq 1 ]; then
    echo "== Key-package freshness (advisory) =="
    if flutter pub outdated --json --show-all >/tmp/_doctor_outdated.json 2>/dev/null; then
      python3 "$SELF_DIR/_doctor_outdated.py" /tmp/_doctor_outdated.json \
        || echo "  (could not parse pub outdated output)"
    else
      echo "  (flutter pub outdated unavailable — skipped)"
    fi
    echo

    echo "== Generator/runtime pairings =="
    pyaml() { grep -qE "^[[:space:]]+$1[[:space:]]*:" pubspec.yaml; }
    pair() { # $1 = runtime test expr, $2 = generator pkg, $3 = human label
      if eval "$1" && ! pyaml "$2"; then
        echo "  ⚠ $3 — dev dep '$2' is missing; build_runner will fail."
      fi
    }
    pair "pyaml flutter_riverpod || pyaml riverpod_annotation" riverpod_generator "Riverpod"
    pair "pyaml mobx || pyaml flutter_mobx" mobx_codegen "MobX"
    pair "pyaml retrofit" retrofit_generator "Retrofit"
    pair "pyaml envied" envied_generator "Envied"
    pair "pyaml json_annotation" json_serializable "json_annotation"
    echo "  ✓ checked (runtime ⇒ generator co-presence; pub get is the real gate)"
    echo

    echo "== Codegen inputs =="
    if grep -RqlE \
      "part '.*\.g\.dart'|part '.*\.freezed\.dart'|@JsonSerializable|@RestApi|@Envied|@freezed|@Freezed" \
      lib 2>/dev/null; then
      echo "• Generated-code inputs present — run:"
      echo "    dart run build_runner build --delete-conflicting-outputs"
    else
      echo "✓ none detected (no build_runner needed)"
    fi
    echo
  else
    echo "(skipping freshness + codegen checks until resolution succeeds)"
    echo
  fi
else
  echo "(no pubspec.yaml here — skipping project checks; run from the project root)"
  echo
fi

# --- skill reference drift scan -------------------------------------------
if [ "$DO_DOCS" -eq 1 ]; then
  echo "== Skill reference drift scan =="
  if [ -d "$REF_DIR" ]; then
    echo "Version-literal mentions to review (package-stack.md &"
    echo "codegen-troubleshooting.md legitimately cite versions, so excluded):"
    grep -rnE "\^[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+" "$REF_DIR" \
      --include='*.md' 2>/dev/null \
      | grep -vE "/(package-stack|codegen-troubleshooting)\.md:" \
      | sed "s#$REF_DIR/#  #" \
      | head -30
    echo "  (verify each still matches current pub.dev / SDK; prefer 'latest-compatible')"
  else
    echo "  (references/ not found next to this script)"
  fi
  echo
fi

if [ "$FAIL" -ne 0 ]; then
  echo "doctor: issues found (see above)."
  exit 1
fi
echo "doctor: OK."
