# Changelog

## V12 — 2026-06-15

**Default-scaffold generator + flavor wrapper** (from a live Flutter 3.44.1 /
Dart 3.12.1 build, verified analyze-clean + 6/6 tests on a throwaway project).

### Added
- `scripts/scaffold_default_features.sh` — drops the validated Full scaffold
  (core/ + app/ + paginated products Bloc + settings HydratedBloc + flavor
  entrypoints + tests + localization), substituting the package name for
  `__PKG__`. Eliminates the ~100k-token hand-emit each new project. Source lives
  in `assets/default-scaffold/` (placeholderized, generated `.g.dart` excluded).
  Ships a `lib/flavors.dart` stub so entrypoints compile before flavorizr runs,
  and removes the demo `widget_test.dart`.
- `scripts/flavorize.sh` — runs `flutter_flavorizr -f` and fixes the three
  documented gotchas in one step (per-flavor iOS `AppIcon-<flavor>` sets;
  asserts `flavorizr.gradle.kts` is written and referenced).

### Changed
- **Model-name consistency:** `products_response_model.dart` → `products_page_model.dart`
  (`ProductsPageModel`) in `project-creation.md` + `feature-generation.md`, matching
  the code samples and the shipped template.
- **`testing.md`:** added a "Repository test" section — type the `Result` cast
  (`as Success<T>`) to avoid `avoid_dynamic_calls`, and omit args equal to model
  defaults to avoid `avoid_redundant_argument_values`.
- **`SKILL.md` / `project-creation.md`:** documented the fast path and the
  required `dart fix --apply` after template scaffolding (own-package imports
  sort to a name-dependent position → `directives_ordering` otherwise).

### Verified
- `eval/run.sh` green on Flutter 3.44.1 / Dart 3.12.1: **23/23 stack scenarios
  PASS** (bloc/riverpod/provider/getx/mobx + all OpenAPI get/by-id/post/put/
  delete/altcore/values/shapes/oneof + riverpod dioprov) **and 5/5 negative
  paths rejected** — no XFAILs. The new scaffold/flavor scripts and doc edits do
  not touch `new_feature.sh`, so the generator eval is unchanged (no regression).

## V1 — 2026-06-11

**Flutter target:** validated on **Flutter 3.44.0 / Dart 3.12.0** (also green on
3.41.0 / Dart 3.11.0). First versioned release.

### Post-release maintenance audit — Flutter 3.41.0 → 3.44.0
- **What broke:** nothing. The full eval — 23 scenarios + 5 negative-path checks
  — passes on 3.44.0 / Dart 3.12.0, identical to the 3.41.0 baseline. No
  PASS→FAIL flips, no analyzer errors, no build_runner failures, under the latest
  `very_good_analysis` lint set.
- **Changed:** no generator or reference changes required (rules: don't change
  what isn't broken).
- **Breaking changes checked but NOT applicable to this skill:**
  - `ListTile` debug error when wrapped in a colored widget — generated
    `ListTile` sits inside `ListView.builder`/`itemBuilder`, not a colored widget.
  - `MediaQuery.of(context).property` → `MediaQuery.propertyOf(context)` — the
    skill uses no `MediaQuery.of()`.
  - `cacheExtent`/`cacheExtentStyle` deprecation — generated lists don't set them.
  - `IconData` / `TextDecoration` marked `final` — skill doesn't extend them.
  - `onReorder` / `ReorderableListView` deprecation — not generated.
  - `RawMenuAnchor` close order; page-transition-builders reorg;
    `TextInputConnection.setStyle`; `ExtendSelectionByPageIntent` removal — unused.
  - Android built-in Kotlin migration — affects `flutter create` Android output,
    not the skill's generated Dart; the eval's build_runner + analyze are unaffected.
- **Pre-existing failures:** none (baseline was fully green).
- **Scenarios affected:** none.

### Verified surface
5 stacks (bloc / riverpod / provider / getx / mobx) × GET / by-id / POST / PUT /
DELETE; oneOf / allOf / maps / nullable model generation; value + runtime +
render gates; presentation→data + domain-purity layer gates; Dio-provider
detection; SDK-floor preflight; `--json` and `--openapi` generators; 5
negative-input paths. SDK switched via a sandboxed 3.44.0 checkout — the global
SDK was not modified.
