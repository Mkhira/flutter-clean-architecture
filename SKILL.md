---
name: flutter-clean-architecture
description: Use this skill when creating a new Flutter project, implementing Flutter or Dart features, writing code in an existing Flutter project, refactoring Flutter/Dart code, or reviewing Flutter code. Trigger whenever the user asks to create a Flutter project/app by name, or when the current workspace is a Flutter project and the task involves implementation, coding, API integration, models, Bloc/Cubit, UI, theming, localization, dependency injection, networking, tests, or code review — even if the user does not explicitly say "clean architecture". For new project creation, ask the user for the directory and project name before running flutter create.
---

# Flutter Clean Architecture

## Purpose

This skill enforces a practical, opinionated, feature-first Flutter Clean
Architecture (presentation / domain / data per feature) so the agent behaves like
a careful senior engineer: UI renders, state coordinates, domain holds
application logic, data talks to the outside world, and infrastructure errors
never leak into widgets. The standardized stack — Bloc/Cubit · Dio+Retrofit ·
JsonSerializable · GetIt · Envied+Flavorizr · Easy Localization (+
`flutter_localizations`) · centralized theme · responsive UI · testing — and its
exact package sets live in `package-stack.md` and the per-area references; load
those, don't restate them here.

## Mode Detection

There are two modes. Detect which one applies before doing anything else.

### New Project Mode

Trigger when the user asks to create a Flutter project/app (e.g. "create flutter
project my_app").

Rules:

- If the user does not give a project name, ask for one.
- If the user gives a name but not the directory path, ask:

  ```text
  Where should I create the project directory?
  ```

- Optionally confirm the organization identifier (`--org`, e.g. `com.example`),
  because it determines the Android `applicationId` and iOS `bundleId` later used
  by flavors. Default to `com.example` only if the user does not care.

#### Scaffold scope: Full vs Lean

A from-scratch **Full** scaffold is large (≈100–140k tokens): products + settings
demo features, multi-flavor Envied + Flutter Flavorizr, full test suite. That is
the right default when the user wants a production-shaped foundation — but it
over-delivers (and over-spends) for a quick start.

- **Full mode (default):** the complete scaffold in `references/project-creation.md`.
- **Lean mode:** trigger when the user says "minimal", "lean", "quick start",
  "barebones", "no demo feature/flavors", or similar. Scaffold only:
  `core/` (DI, theme, localization, router, network, error) + `app/` + a single
  minimal home screen (e.g. the `counter` Cubit from `bloc-cubit.md`, or an empty
  `HomePage`). **Skip** the products & settings demo features, **skip**
  flavorizr/multi-flavor (use a single `main.dart` + one `.env` or
  `--dart-define`), and add only the packages that minimal set needs. Still set up
  `analysis_options.yaml`, localization assets, DI, and theme.

If the scope is ambiguous for a from-scratch project, ask once (one line:
"Full scaffold with demo feature + flavors, or a lean minimal start?") rather than
defaulting to the heavy build silently.

#### State-management stack

After name/directory/org, ask **once**:

```text
Which state management stack?
  1. Bloc/Cubit (default)   2. Riverpod   3. Provider   4. GetX   5. MobX
```

If the user does not choose (or the run is non-interactive), **default to
Bloc/Cubit**. The chosen stack only changes the **presentation layer + its DI
wiring** — domain and data are identical for every stack. The stack adds its
packages on top of the base set; see the per-stack sets in `package-stack.md`.
Load **only** that stack's reference (below) — e.g. a Riverpod project reads
`references/riverpod.md` *instead of* `references/bloc-cubit.md`.

Do not run `flutter create` until the name and directory are known. If the user
gives both name and directory, proceed.

Then follow `references/project-creation.md` (and apply Lean trimming above when
Lean mode is selected). For the **Full** scaffold, prefer the fast path —
`scripts/scaffold_default_features.sh .` drops the validated, analyze-clean
core/app/products/settings code (substituting the package name) instead of
hand-emitting ~100k tokens; then `scripts/flavorize.sh` for flavors. See the
"Fast path" note at the top of `project-creation.md`.

### Existing Project Mode

Trigger when:

- `pubspec.yaml` exists and contains `flutter:`, or
- `pubspec.yaml` depends on the Flutter SDK, or
- the user mentions Flutter/Dart implementation, coding, review, refactor,
  Bloc/Cubit, widget, route, API, model, repository, theme, or feature.

Inspect before coding:

```text
pubspec.yaml
analysis_options.yaml
lib/
test/
existing feature folders
existing routing setup
existing DI setup
existing state management
existing theme setup
existing codegen/build.yaml
```

**Detect the state-management stack first.** Before adding a feature or layer,
run `scripts/detect_stack.sh` (prints `bloc|riverpod|provider|getx|mobx|unknown`)
and generate in that stack — load its reference (below) instead of
`bloc-cubit.md`. If `unknown`, ask. **Never impose Bloc on a non-Bloc project.**

Follow existing project conventions unless the user explicitly asks to migrate or
to establish the architecture. A consistent existing convention beats this
skill's defaults.

## Progressive Reference Loading

Read only what the task needs.

- **Always** read `references/architecture.md`.
- **New projects:** also read `references/project-creation.md`,
  `references/package-stack.md`, `references/env-and-flavors.md`,
  `references/localization.md`, `references/theme.md`,
  `references/dependency-injection.md`, `references/routing.md`, and
  `references/testing.md`.
- **Feature implementation:** read `references/feature-generation.md`, the
  **active stack's reference** (below), and the relevant domain files. Scaffold the
  skeleton with `scripts/new_feature.sh <ui|api|form> <name>` first (saves output
  tokens), then fill the logic. For a plural feature name, add `--item <singular>`
  so the entity/model are singular (e.g. `api elixirs --item elixir`). Add
  `--json <file>` to infer the entity/model (incl. nested types) from a sample
  response instead of the single-`id` stub. If the API has an OpenAPI/Swagger
  spec, prefer `--openapi <spec> --path <endpoint>`: it generates exact types
  **and** the Retrofit client + Dio-backed datasource from the contract.
- **State management — load ONLY the active stack (it replaces `bloc-cubit.md`,
  it does not stack on top):** `bloc-cubit.md` (default) · `riverpod.md` ·
  `provider.md` · `getx.md` · `mobx.md`. Domain/data are identical regardless;
  only presentation + DI wiring differ.
- **Dio/Retrofit work:** read `references/api-contracts.md`,
  `references/networking.md`, `references/models-and-codegen.md`, and
  `references/errors-and-results.md`.
- **build_runner / codegen failures:** read `references/codegen-troubleshooting.md`
  the moment a generation step errors (don't blind-retry).
- **Auth/token work:** read `references/auth-and-secure-storage.md`.
- **UI/styling work:** read `references/theme.md` and `references/responsive-ui.md`.
- **Assets / images / SVG / fonts:** read `references/assets-and-codegen.md`
  (flutter_gen type-safe accessors, the flutter_svg silent-failure gotcha,
  resolution-aware images, fonts).
- **Golden / integration tests:** see those sections in `references/testing.md`
  (goldens are flaky without font loading + a controlled env — use alchemist).
- **Forms:** read `references/forms.md`.
- **Localization:** read `references/localization.md`.
- **Connectivity:** read `references/connectivity.md`.
- **Logging:** read `references/logging.md`.
- **Review work:** read `references/review-checklist.md`.

## Non-Negotiable Rules

- Do not invent API request/response models. Ask for JSON request/response
  examples unless they already exist in the repo, Swagger/OpenAPI/Postman docs,
  tests, or a backend contract.
- Do not expose `DioException` to UI.
- Do not place business logic inside widgets.
- Do not add packages to an existing project unless needed.
- Do not introduce a new state management package; use Bloc/Cubit unless the
  existing project clearly uses another pattern.
- Do not edit generated files manually.
- Do not hardcode colors/text styles in widgets when a theme token exists;
  consume the theme.
- Run `dart run build_runner build --delete-conflicting-outputs` only after
  editing files related to `.g.dart`, `.freezed.dart`, Retrofit, Envied,
  JsonSerializable, or Freezed. (Newer build_runner — 2.15+ — has removed
  `--delete-conflicting-outputs` and now ignores it with a harmless warning;
  the flag is still safe to pass for older versions, so keep it.)
- For normal UI/Cubit/repository/usecase edits, do not run build_runner unless
  generated-code inputs changed.
- Do not introduce a `bootstrap.dart` / `bootstrap()` indirection. Flutter's
  entrypoint convention is `main()` in `main.dart`. Put startup directly in
  `main()`; if multiple flavor entrypoints must share startup, factor it into a
  clearly named function (e.g. `runApplication()`) in the app composition root
  (`app/app.dart`), not a `bootstrap` file.
- Use latest compatible package versions. Prefer `flutter pub add package_name`
  / `flutter pub add dev:package_name` so Pub resolves the latest compatible
  version. If exact versions are written, verify latest first.
- For new project creation, always ask for project name and target directory if
  missing.

## Validation Workflow

- **Preflight** with `scripts/doctor.sh` before building features or after
  touching `pubspec.yaml`: it checks the SDK, runs `flutter pub get` (and points
  at the conflict playbook if resolution fails), and reports outdated key
  packages. `--docs` also scans references for stale version mentions.
- Run `dart format .` after edits.
- Run `dart fix --apply` after scaffolding a project from a template (e.g.
  `scripts/scaffold_default_features.sh`): the project's own `package:<name>/...`
  imports sort to a name-dependent position, so a template authored for one name
  trips `directives_ordering` under another. `dart fix --apply` normalizes it.
- Run `flutter analyze` for Flutter projects.
- After any domain-layer edit, run `scripts/check_layers.sh` — it fails if a
  `domain/` file imports Flutter/Dio/GetIt/etc. Keep the domain pure (see
  `references/architecture.md`).
- Run relevant `flutter test` when tests exist or behavior changed. **Use the
  compact reporter and scope to what changed** to keep output (and token cost)
  small: `flutter test -r compact test/path/to/changed_test.dart`. The default
  expanded reporter prints a progress line per test — several thousand tokens per
  run; `-r compact` collapses that to a single updating line. Only run the whole
  `test/` suite (still with `-r compact`) for a final pass.
- Run `dart run build_runner build --delete-conflicting-outputs` only when
  generated-code inputs changed.
- Use `scripts/validate_flutter_project.sh` when appropriate (it runs pub get,
  conditional build_runner, format, analyze, and tests). Its steps are quiet on
  success (one `✓ <step>` line each) and print diagnostics only on failure;
  during iteration scope `flutter analyze` to `lib/features/<feature>`, full
  `lib` only on the final pass.
