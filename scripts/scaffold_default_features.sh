#!/usr/bin/env bash
#
# scaffold_default_features.sh — drop the validated, analyze-clean DEFAULT
# scaffold (core/ + app/ + products + settings + flavor entrypoints + tests +
# localization) onto a freshly-created Flutter project, substituting the
# project's package name. This is the Full new-project scaffold from
# references/project-creation.md as a known-good template, so the agent does NOT
# re-emit ~100k tokens of boilerplate by hand each time.
#
# Usage (run from, or pass, the Flutter project root):
#   scripts/scaffold_default_features.sh [project_root]
#
#   [project_root]   defaults to "." (must contain pubspec.yaml)
#
# What it writes (never overwrites an existing products feature):
#   lib/core/**            error/result, env (Envied per-flavor), network (Dio),
#                          theme (light+dark + AppTokens), router (go_router), di
#   lib/app/**             app composition root (runApplication) + BlocObserver
#   lib/features/products  paginated infinite-scroll Bloc + fake datasource
#   lib/features/settings  HydratedBloc (persisted locale + theme mode)
#   lib/main*.dart         default + per-flavor entrypoints
#   test/features/**       products bloc + repository + settings bloc tests
#   assets/lang/{en,ar}.json, .env.{dev,staging,prod}, analysis_options.yaml
#
# It substitutes the package name read from pubspec.yaml for the __PKG__
# placeholder. After it runs, add the packages (see package-stack.md), run
# build_runner, then scripts/flavorize.sh. It prints those exact next steps.
#
set -euo pipefail

ROOT="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$SCRIPT_DIR/../assets/default-scaffold"

die() { echo "error: $*" >&2; exit 1; }

[ -f "$ROOT/pubspec.yaml" ] || die "no pubspec.yaml in '$ROOT' (run from the Flutter project root or pass it)"
[ -d "$TPL" ] || die "scaffold template missing at $TPL"

PKG=$(awk -F': *' '/^name:/{gsub(/[" ]/,"",$2); print $2; exit}' "$ROOT/pubspec.yaml")
[ -n "$PKG" ] || die "could not read 'name:' from $ROOT/pubspec.yaml"

[ -e "$ROOT/lib/features/products" ] && \
  die "lib/features/products already exists — refusing to overwrite. Remove it first to re-scaffold."

echo "==> Scaffolding default features into '$ROOT' (package: $PKG)"

# Dart/JSON/yaml tree (lib, test, assets, analysis_options.yaml), with __PKG__
# substituted. analysis_options.yaml is skipped if it already uses very_good.
copied=0
while IFS= read -r rel; do
  src="$TPL/$rel"
  dst="$ROOT/$rel"
  if [ "$rel" = "analysis_options.yaml" ] && [ -f "$dst" ] && \
     grep -q 'very_good_analysis' "$dst"; then
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  sed "s/__PKG__/$PKG/g" "$src" > "$dst"
  copied=$((copied + 1))
done < <(cd "$TPL" && find lib test assets analysis_options.yaml -type f | sort)

# Env files live under env/ in the template; land them at the project root.
for f in dev staging prod; do
  cp "$TPL/env/.env.$f" "$ROOT/.env.$f"
  copied=$((copied + 1))
done

# Remove flutter create's default widget test — it references the demo MyApp
# widget this scaffold deletes, so it breaks analyze/test if left (see
# project-creation.md step 9). The real feature tests replace it.
if [ -f "$ROOT/test/widget_test.dart" ]; then
  rm -f "$ROOT/test/widget_test.dart"
  echo "==> Removed default test/widget_test.dart (referenced the deleted MyApp)."
fi

echo "==> Wrote $copied files."
cat <<EOF

Next steps (the scaffold assumes these packages/build are in place):

  1. Add the base + Bloc package set (resolve latest — see package-stack.md):
       flutter pub add flutter_bloc bloc equatable bloc_concurrency hydrated_bloc \\
         get_it dio retrofit go_router json_annotation envied \\
         cached_network_image flutter_screenutil_plus path_provider easy_localization
       flutter pub add flutter_localizations --sdk=flutter
       flutter pub add dev:build_runner dev:json_serializable dev:retrofit_generator \\
         dev:envied_generator
       flutter pub add dev:bloc_test dev:mocktail dev:flutter_flavorizr dev:very_good_analysis

  2. Wire assets/lang into pubspec.yaml (flutter: assets: - assets/lang/) and
     add CFBundleLocalizations (en, ar) to ios/Runner/Info.plist.

  3. Generate code (Envied/.env.* already present, JsonSerializable, Retrofit):
       dart run build_runner build --delete-conflicting-outputs

  4. Set up flavors (overwrites the lib/flavors.dart stub with the real enum;
     the entrypoints already import it):
       author flavorizr.yaml (see env-and-flavors.md), then
       scripts/flavorize.sh

  5. Normalize import ordering for THIS package name, then validate. The own-
     package imports (package:$PKG/...) sort to a name-dependent position, so
     'dart fix --apply' is REQUIRED to keep directives_ordering clean:
       dart fix --apply
       scripts/validate_flutter_project.sh
EOF
