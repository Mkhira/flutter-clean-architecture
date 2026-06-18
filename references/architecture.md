# Architecture

Feature-first Clean Architecture. Each feature owns its own presentation,
domain, and data layers; shared infrastructure lives under `core/`.

## Folder layout

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   └── app_bloc_observer.dart
├── core/
│   ├── di/
│   ├── env/
│   ├── network/
│   ├── error/
│   ├── router/
│   └── theme/
└── features/
    └── feature_name/
        ├── presentation/
        │   ├── cubit/ or bloc/
        │   ├── pages/
        │   └── widgets/
        ├── domain/
        │   ├── entities/
        │   ├── repositories/
        │   └── usecases/
        └── data/
            ├── datasources/
            ├── models/
            └── repositories/
```

`bootstrap/` is **not** a Clean Architecture layer, and `bootstrap.dart` is not
a Flutter convention — it is a Very Good Ventures idiom. Do not create a
top-level `bootstrap/` folder or a `bootstrap.dart` / `bootstrap()` function.
Flutter's entrypoint convention is `main()` in `main.dart`: put startup there.
If multiple flavor entrypoints must share startup, factor it into a clearly
named function such as `runApplication()` in the app composition root
(`app/app.dart`) — see `env-and-flavors.md`.

## Dependency rules

```text
presentation -> domain
data -> domain
core can support all layers
domain must not depend on Flutter, Dio, Retrofit, GetIt, or UI
data may depend on Dio/Retrofit/JsonSerializable
presentation may depend on Flutter and Bloc/Cubit
```

The domain layer is pure Dart: entities, repository contracts (abstract), and
use cases. If you find yourself importing `package:flutter`, `package:dio`, or
`package:get_it` into a domain file, the boundary is wrong.

### Enforce it — don't just honor it in prose

A boundary that lives only in a guideline rots: one careless edit puts
`package:flutter` in an entity and nothing breaks, so it spreads. Make it a build
gate instead. The skill ships `scripts/check_layers.sh`, which enforces **two**
boundaries and fails (exit 1) if either is crossed:

1. **Domain purity** — no Dart file under a `domain/` directory may import a
   banned framework/infrastructure package (Flutter, Dio, Retrofit, GetIt,
   json_annotation, bloc/flutter_bloc, hydrated_bloc, go_router, persistence, …).
   Pure-Dart packages (`equatable`, `fpdart`, `meta`, …) and `dart:` imports stay
   allowed.
2. **Presentation → data** — no file under a `presentation/` directory may import
   a feature's `data/` layer (concrete models, datasources, repository impls),
   via either a `package:` or a relative import. Widgets and state holders depend
   on the domain contract; concrete data types are constructed only in the DI
   composition root. The **one** exception is a Riverpod composition file
   (carries `@riverpod`) — there, providers *are* the DI wiring, so it may
   legitimately reference data impls. Generated `*.g.dart` / `*.freezed.dart`
   files are skipped.

```bash
scripts/check_layers.sh            # checks lib/ by default
scripts/check_layers.sh lib        # explicit root
```

Run it after domain edits and wire it into CI (and `scripts/validate_flutter_project.sh`)
so the boundary stays clean without depending on review. For IDE-time feedback,
the config-only upgrade is an `import_lint` rule banning the same packages under
`**/domain/**`; a hand-written `custom_lint` plugin is the heavier option and
usually not worth the maintenance for an app.

## Practical SOLID mapping

- **SRP:** widgets render, cubits/blocs coordinate state, use cases execute
  application actions, repositories abstract data, datasources call APIs/cache.
- **OCP:** add new implementations without rewriting consumers (new datasource,
  new repository impl, behind the same contract).
- **LSP:** repository implementations must honor their domain contract —
  same return semantics, same failure surface.
- **ISP:** avoid giant repository interfaces; split by capability.
- **DIP:** domain depends on abstractions, data implements them.

## Anti-overengineering rules

- Do not create use cases for trivial UI-only behavior.
- Do not create abstract repositories for local-only or temporary code unless
  there is a real boundary (a swappable data source, a testability need).
- Do not create empty folders.
- Do not split tiny widgets just to split them.
- Follow existing repo conventions when stronger than the default.

The goal is boundaries that earn their keep. A static "About" page does not need
a domain layer.

## Examples

Worked feature examples — UI-only, the default counter, and the extended
**products** paginated API feature — plus the implementation flow live in
`feature-generation.md` (loaded for feature tasks). This file keeps the
contracts (folder tree, dependency rules, SOLID, enforcement); the worked
walkthroughs live there so a feature task doesn't pay for both copies.
