#!/usr/bin/env bash
#
# detect_stack.sh — print the state-management stack a Flutter project uses, so
# the generator adds features in the project's OWN stack (never imposes Bloc).
#
# Prints exactly one of: bloc | riverpod | provider | getx | mobx | unknown
#
# Method:
#   1. inspect pubspec.yaml dependencies;
#   2. if several match, break the tie by the dominant pattern actually used
#      under lib/**/presentation, and note the ambiguity on stderr;
#   3. if none (or still ambiguous), print "unknown" — the caller should ask.
#
# Usage: scripts/detect_stack.sh [project_root]   (default: .)
#
set -uo pipefail

ROOT="${1:-.}"
PUBSPEC="$ROOT/pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
  echo "unknown"
  echo "detect_stack: no pubspec.yaml at '$ROOT'." >&2
  exit 0
fi

# Only scan the dependency section (stop at dev_dependencies is fine — stacks
# are runtime deps). Match package names at the start of a yaml key.
dep() { grep -qE "^[[:space:]]+$1[[:space:]]*:" "$PUBSPEC"; }

present=()
{ dep 'flutter_bloc' || dep 'bloc'; } && present+=(bloc)
{ dep 'flutter_riverpod' || dep 'hooks_riverpod' || dep 'riverpod_annotation'; } \
  && present+=(riverpod)
dep 'provider' && present+=(provider)
# `get` is the GetX package. This matches the `get:` key only — `get_it` won't
# trip it, because dep()'s `[[:space:]]*:` after the name requires `get` to be
# the whole yaml key, not a prefix of `get_it`.
dep 'get' && present+=(getx)
{ dep 'mobx' || dep 'flutter_mobx'; } && present+=(mobx)

count=${#present[@]}

if [ "$count" -eq 1 ]; then
  echo "${present[0]}"
  exit 0
fi

if [ "$count" -eq 0 ]; then
  echo "unknown"
  echo "detect_stack: no known state-management package in pubspec.yaml." >&2
  exit 0
fi

# Tie-break: count usage markers under presentation directories.
echo "detect_stack: multiple stacks in pubspec (${present[*]}); breaking tie by usage." >&2
pres_files="$(find "$ROOT/lib" -type f -name '*.dart' -path '*/presentation/*' 2>/dev/null || true)"
score() { [ -z "$pres_files" ] && { echo 0; return; }; printf '%s\n' "$pres_files" | xargs grep -lE "$1" 2>/dev/null | wc -l | tr -d ' '; }

declare -A scores
for s in "${present[@]}"; do
  case "$s" in
    bloc) scores[bloc]=$(score 'BlocBuilder|BlocProvider|BlocListener|BlocConsumer|context\.read<|context\.watch<') ;;
    riverpod) scores[riverpod]=$(score 'ConsumerWidget|ConsumerState|ref\.watch|ref\.read|@riverpod') ;;
    provider) scores[provider]=$(score 'ChangeNotifierProvider|Consumer<|context\.watch<|context\.select') ;;
    getx) scores[getx]=$(score 'GetxController|Obx\(|GetBuilder') ;;
    mobx) scores[mobx]=$(score 'Observer\(|with Store|@observable|@action') ;;
  esac
done

best=unknown
best_n=-1
for s in "${present[@]}"; do
  n=${scores[$s]:-0}
  if [ "$n" -gt "$best_n" ]; then best_n=$n; best=$s; fi
done

if [ "$best_n" -le 0 ]; then
  echo "unknown"
  echo "detect_stack: deps present (${present[*]}) but no dominant usage found — ask the user." >&2
else
  echo "$best"
  echo "detect_stack: chose '$best' by usage (scores: $(for s in "${present[@]}"; do printf '%s=%s ' "$s" "${scores[$s]:-0}"; done))." >&2
fi
