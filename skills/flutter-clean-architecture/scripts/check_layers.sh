#!/usr/bin/env bash
#
# check_layers.sh — enforce Clean Architecture layer boundaries.
#
# Two gates, both turning a prose rule into a build gate (exit 1 on violation):
#
#   1. domain purity   — files under domain/ must stay pure Dart: entities,
#      abstract repository contracts, use cases. No Flutter, networking, DI,
#      codegen, state-management, or persistence imports.
#
#   2. presentation -> data — widgets/state-holders must depend on the domain
#      contract, not concrete data/ types. The ONE allowed exception is a
#      Riverpod DI composition file (carries `@riverpod`): in Riverpod, providers
#      ARE the DI wiring, so that file may legitimately know data impls. Every
#      other presentation file (pages, widgets, blocs/cubits/controllers/stores)
#      must not import data/. (Generated *.g.dart/*.freezed.dart are skipped.)
#
# Usage:
#   scripts/check_layers.sh [root]     # root defaults to "lib"
#
set -euo pipefail

ROOT="${1:-lib}"

# Packages the domain layer must not depend on (UI / DI / networking / codegen /
# persistence / state-management infra). Pure-Dart packages (equatable, fpdart,
# meta, collection, intl, ...) and `dart:` imports remain allowed.
BANNED='flutter|flutter_bloc|bloc|bloc_concurrency|hydrated_bloc|flutter_riverpod|hooks_riverpod|riverpod_annotation|flutter_hooks|provider|get|mobx|flutter_mobx|dio|retrofit|get_it|json_annotation|freezed_annotation|go_router|cached_network_image|easy_localization|flutter_screenutil|flutter_screenutil_plus|envied|path_provider|shared_preferences|hive|sqflite'

if [ ! -d "$ROOT" ]; then
  echo "check_layers: '$ROOT' is not a directory." >&2
  exit 2
fi

status=0

# --- Gate 1: domain purity --------------------------------------------------
domain_files="$(find "$ROOT" -type f -name '*.dart' -path '*/domain/*' 2>/dev/null || true)"

if [ -z "$domain_files" ]; then
  echo "check_layers: no domain/ Dart files under '$ROOT' — skipping domain-purity gate."
else
  # Match real import directives only (anchored), for package: imports in the
  # banned set. Avoids false positives from comments and string literals.
  violations="$(printf '%s\n' "$domain_files" \
    | xargs grep -nE "^[[:space:]]*import[[:space:]]+['\"]package:($BANNED)/" 2>/dev/null || true)"

  if [ -n "$violations" ]; then
    status=1
    echo "✗ Clean Architecture violation — the domain layer imports framework/infrastructure:"
    echo
    printf '%s\n' "$violations"
    echo
    echo "Fix: move that logic outward."
    echo "  • UI / state / DI  -> presentation/ (or core/di)"
    echo "  • networking / models / persistence -> data/"
    echo "Domain stays pure Dart: entities, abstract repository contracts, use cases."
    echo
  fi
fi

# --- Gate 2: presentation must not import data ------------------------------
# An app-internal import that reaches into a feature's data/ layer. Covers both
# package: imports (package:<pkg>/features/<f>/data/...) and relative imports
# (../data/..., ../../data/...). The `/data/` segment boundary avoids matching
# unrelated names like `metadata/`.
DATA_IMPORT="^[[:space:]]*import[[:space:]]+['\"](package:[^'\"]+/features/[^'\"]+/data/|\.[^'\"]*/data/)"

pres_files="$(find "$ROOT" -type f -name '*.dart' -path '*/presentation/*' 2>/dev/null || true)"

if [ -z "$pres_files" ]; then
  echo "check_layers: no presentation/ Dart files under '$ROOT' — skipping presentation->data gate."
else
  pres_violations=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      *.g.dart|*.freezed.dart) continue ;;   # generated — not authored boundaries
    esac
    # Riverpod composition root: providers ARE the DI wiring, so this file may
    # know concrete data impls. Identified by the @riverpod annotation.
    if grep -q '@riverpod' "$f" 2>/dev/null; then
      continue
    fi
    hits="$(grep -nE "$DATA_IMPORT" "$f" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
      pres_violations="${pres_violations}${f}:\n${hits}\n"
    fi
  done <<EOF
$pres_files
EOF

  if [ -n "$pres_violations" ]; then
    status=1
    echo "✗ Clean Architecture violation — presentation imports the data layer directly:"
    echo
    printf '%b' "$pres_violations"
    echo
    echo "Fix: depend on the domain contract, not concrete data types."
    echo "  • Call a use case (or the abstract repository) from the state holder."
    echo "  • Construct concrete data impls only in the DI composition root"
    echo "    (core/di for GetIt stacks; an @riverpod provider for Riverpod)."
    echo
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "✓ Layers are clean — domain pure, presentation free of data imports."
fi
exit "$status"
