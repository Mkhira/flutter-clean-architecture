# Package Stack

> **Dart SDK floor:** generated features use Dart 3 language features (sealed
> classes, switch-expression patterns, `final class`), so the target project
> needs `environment: sdk: '^3.0.0'` or newer. `scripts/doctor.sh` and
> `scripts/new_feature.sh` detect the current/declared SDK and warn if it's below
> that — this is a floor, not a version to hand-pin.

```text
ALWAYS resolve the latest compatible version with `flutter pub add <package>`
(and `flutter pub add dev:<package>` for dev dependencies). Let Pub pick versions
— do NOT hand-pin from the numbers below; they are illustrative baselines that may
already be outdated. Verify on pub.dev and confirm cross-package compatibility:
  - bloc_test major must match the installed bloc major
  - retrofit_generator must match retrofit
  - envied_generator must match envied
  - hydrated_bloc must be compatible with the installed bloc/flutter_bloc
```

## Common resolution conflict (codegen + test vs json_annotation)

Adding the codegen + test dev-deps together can fail version solving. The usual
culprit: `flutter pub add json_annotation` grabs the newest `json_annotation`
(e.g. `^4.12.0`), but the `json_serializable` that `flutter_test`/`bloc_test`
(which pin `analyzer`/`test_api`/`matcher`) can resolve to only allows an older
`json_annotation` (e.g. `>=4.11.0 <4.12.0`) — so no solution exists.

Fix without fighting the solver:
1. Add the dev-deps in groups, not all at once, so the failing package is obvious.
2. **Relax `json_annotation` to the band `json_serializable` accepts** — use the
   bounded band `'>=4.11.0 <4.12.0'`, **not** `^4.11.0`. A caret `^4.11.0` still
   resolves *up* to `4.12.0` (it means `>=4.11.0 <5.0.0`), so the newest
   `json_serializable` is pulled back in and the conflict returns. Only the upper
   bound `<4.12.0` forces the older `json_serializable` that the SDK's pinned
   `analyzer`/`matcher` can satisfy. Set
   `json_annotation: '>=4.11.0 <4.12.0'` in `pubspec.yaml`, then
   `flutter pub get`. Tighten back up only after confirming the resolved
   versions.

Do not pin `analyzer`/`test_api`/`matcher` by hand to force it — that fights the
Flutter SDK's own constraints. Relax the leaf dep (`json_annotation`) instead.

## Dependencies (illustrative baselines — resolve fresh with `pub add`)

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  flutter_bloc: ^9.0.0
  bloc: ^9.0.0
  equatable: ^2.0.5
  bloc_concurrency: ^0.3.0
  hydrated_bloc: ^10.0.0
  dio: ^5.0.0
  retrofit: ^4.0.0
  json_annotation: ^4.9.0
  envied: ^1.0.0
  get_it: ^8.0.0
  cached_network_image: ^3.4.0
  flutter_screenutil_plus: ^1.5.0
  path_provider: ^2.1.0
  easy_localization: ^3.0.0
```

## Dev dependencies (illustrative baselines — resolve fresh with `pub add`)

```yaml
dev_dependencies:
  retrofit_generator: ^9.0.0
  json_serializable: ^6.8.0
  build_runner: ^2.4.0
  flutter_flavorizr: ^2.5.0
  envied_generator: ^1.0.0
  bloc_test: ^10.0.0
  mocktail: ^1.0.0
```

`bloc_test` and `flutter_bloc`/`bloc` versions must be compatible — confirm the
pairing with `pub add` rather than copying these numbers. Same for
`retrofit_generator`/`retrofit` and `envied_generator`/`envied`.

## State-management stacks (pick one — adds to the base)

The lists above are the **Bloc default**. The **base** (everything except the
state-management + DI + persistence packages — i.e. `dio`, `retrofit`,
`json_annotation`, `envied`, `go_router`, `easy_localization`,
`flutter_screenutil_plus`, `cached_network_image`, `path_provider`, +
`flutter_localizations`, + codegen/test dev-deps) is **identical for every
stack**. Only the state/DI/persistence packages swap. Resolve every version with
`flutter pub add` / `flutter pub add dev:<pkg>` — never hand-pin. Add the codegen
+ test dev-deps in groups (the `json_annotation`/`json_serializable` solver
conflict above still applies).

| Stack | add (deps) | add (dev) | DI | persist | codegen |
|---|---|---|---|---|---|
| **Bloc** (default) | flutter_bloc, bloc, equatable, bloc_concurrency, hydrated_bloc, get_it | bloc_test, mocktail | GetIt | HydratedBloc | no |
| **Riverpod** | flutter_riverpod, hooks_riverpod, flutter_hooks, riverpod_annotation, shared_preferences | riverpod_generator, riverpod_lint, build_runner, mocktail | **providers (no get_it)** | shared_preferences | **yes** |
| **Provider** | provider, get_it, shared_preferences | mocktail | GetIt | shared_preferences | no |
| **GetX** | get, get_it, shared_preferences | mocktail | GetIt | shared_preferences | no |
| **MobX** | mobx, flutter_mobx, get_it, shared_preferences | mobx_codegen, build_runner, mocktail | GetIt | shared_preferences | **yes** |

Constraints (document loudly so a stack doesn't swallow the architecture):
- **Riverpod:** providers ARE the DI — do **not** add `get_it`. `ProviderScope`
  at the root; repositories/use cases are `Provider`s; tests use
  `ProviderContainer` + overrides.
- **GetX:** use GetX for **presentation state only** (`GetxController` + `Obx`).
  Keep **GetIt** for DI and **go_router** for routing. Do **not** use `Get.put`/
  `Get.find` for repos/use cases or `GetMaterialApp`/GetX routing.
- **MobX:** ships no DI, so use **get_it** (consistent with the rest of the skill).
- Non-Bloc stacks have no HydratedBloc → persist settings (locale/theme) via
  **shared_preferences**.

## Recommended optional

```yaml
dependencies:
  go_router: latest-compatible
  flutter_secure_storage: latest-compatible
  logger: latest-compatible
  connectivity_plus: latest-compatible
  internet_connection_checker_plus: latest-compatible
  formz: latest-compatible
  fpdart: latest-compatible
  freezed_annotation: latest-compatible
  flutter_svg: latest-compatible            # SVG assets (see assets-and-codegen.md)

dev_dependencies:
  freezed: latest-compatible
  very_good_analysis: latest-compatible
  flutter_gen_runner: latest-compatible     # type-safe asset accessors
  alchemist: latest-compatible              # golden tests (font/CI-safe)
```

`integration_test` (end-to-end tests) ships with the Flutter SDK:

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

## Rules

- `equatable` is the default for simple immutable states/entities.
- `freezed` is optional/preferred for complex unions, larger API models, and
  complex state.
- Use `very_good_analysis` for new projects if the SDK supports it; otherwise
  `flutter_lints`.
- Avoid `dartz`; prefer a custom `Result` or `fpdart`.
- Never pin old versions without checking current compatibility.
- For existing projects, avoid package churn — add only what the task needs.
