# Flutter Clean Architecture — What It Is & How It Works

> A plain-English explainer of this skill: what problem it solves, how it
> behaves at runtime, and what every part of the skill folder does. For the
> task-by-task practical guide see `README.md`; for the full ask-anything
> capability table see `CAPABILITIES.md`; the authoritative agent behavior lives
> in `SKILL.md` + `references/`.

---

## 1. What this skill is (in one paragraph)

`flutter-clean-architecture` is an **opinionated architecture-and-codegen skill**
that makes the agent build Flutter apps like a careful senior engineer instead of
ad-hoc. Whenever you create a Flutter project or touch Flutter/Dart code, it
activates and enforces a **feature-first Clean Architecture** — every feature is
split into `presentation / domain / data` layers, infrastructure errors never
leak into widgets, and the layer boundaries are guarded by **executable gates**,
not just prose. It ships **code generators** that turn an API contract (OpenAPI or
a sample JSON) into real, type-safe Dart, supports **five state-management
stacks**, and proves its own output with a **23-scenario evaluation harness**.

The core promise: **UI renders · state coordinates · domain holds application
logic · data talks to the outside world · errors are mapped before they reach the
screen.**

---

## 2. The mental model

The skill is **not** a set of fixed sub-commands. It is driven by
**natural-language intent**: you describe what you want ("add an orders feature
from this swagger", "add dark mode", "review this against SOLID") and the skill
routes the request to the right *playbook* (a reference doc) and the right
*generator* (a script). Three ideas hold it together:

1. **Feature-first layering.** Code is organized by feature, and each feature owns
   its three layers. Shared infrastructure (DI, theme, router, network, error,
   env) lives once under `core/`.

2. **The dependency rule is the whole point.** Dependencies point *inward* toward
   the domain. `domain/` is **pure Dart** — it may not import Flutter, Dio,
   Retrofit, GetIt, json_annotation, or bloc. This keeps business logic testable
   and framework-independent.

3. **Boundaries that earn their keep.** It is opinionated but not dogmatic — it
   has explicit *anti-overengineering* rules (no use case for trivial UI, no
   abstract repo for local-only state, no empty folders). A static "About" page
   does not get a domain layer.

```
        ┌─────────────────────────────────────────────┐
        │                presentation/                 │  Flutter + Bloc/Cubit/etc.
        │   widgets · pages · state holder (per stack) │  renders & coordinates
        └───────────────────────┬─────────────────────┘
                                │  depends on ▼ (contracts only)
        ┌───────────────────────┴─────────────────────┐
        │                   domain/                    │  PURE DART
        │   entities · repository contracts · usecases │  application logic
        └───────────────────────▲─────────────────────┘
                                │  implements ▲
        ┌───────────────────────┴─────────────────────┐
        │                    data/                     │  Dio · Retrofit · JsonSerializable
        │   models · datasources · repository impls    │  maps errors → domain failures
        └─────────────────────────────────────────────┘

        core/  (di · env · network · error · router · theme)  supports all layers
```

Two boundaries are **mechanically enforced** by `scripts/check_layers.sh`:
- **Domain purity** — no `domain/` file imports a banned framework/infra package.
- **Presentation → data** — no `presentation/` file imports a feature's concrete
  `data/` layer (the one exception: a Riverpod `@riverpod` composition file, since
  there providers *are* the DI wiring).

---

## 3. How it activates

### Triggers
- **Explicit slash command:** `/flutter-clean-architecture <free text>`.
- **Automatic:** any Flutter/Dart task in a Flutter repo activates it — even
  without saying "clean architecture" (implementing a feature, models, Bloc/Cubit,
  UI, theming, localization, DI, networking, tests, or review).

### Two modes (auto-detected)

| Mode | Detected when | What happens |
|---|---|---|
| **New Project** | You ask to create an app by name | Asks for **name + directory** (and optionally `--org`), offers **Full** or **Lean** scope, asks which **stack**, then scaffolds. It will **not** run `flutter create` until name + directory are known. |
| **Existing Project** | A `pubspec.yaml` with Flutter exists, or you mention Flutter work | **Inspects your conventions first** (pubspec, analysis_options, lib/, routing, DI, theme, codegen), **detects your state-management stack** (`scripts/detect_stack.sh`), and follows them. It never imposes Bloc on a non-Bloc project. |

### New-project scope: Full vs Lean
- **Full (default)** — production-shaped foundation: `core/` + `app/` + a
  paginated **products** demo feature + a **settings** HydratedBloc + multi-flavor
  Envied + Flutter Flavorizr + full test suite. (~100–140k tokens.)
- **Lean** — triggered by "minimal / lean / quick start / barebones / no demo or
  flavors": just `core/` + `app/` + one minimal home screen, single `main.dart`,
  no flavorizr, only the packages that minimal set needs. (~half of Full.)

---

## 4. How it works, end to end

A typical **"add an API feature"** request flows like this:

```
1. INTENT        you: "add an elixirs feature from this swagger, path /Elixirs"
        │
2. ROUTE         skill reads architecture.md + feature-generation.md
        │        + the ACTIVE stack reference (e.g. bloc-cubit.md)
        │
3. SCAFFOLD      scripts/new_feature.sh api elixirs --item elixir \
        │            --openapi swagger.json --path /Elixirs --stack bloc
        │        → generates exact entity + model (+ nested) + Retrofit client
        │          + Dio datasource + repo + use case + Cubit + Page on disk
        │
4. FILL          agent opens ONLY the files marked TODO(you) and writes the
        │        real logic; FINAL files are never re-opened (token saver)
        │
5. WIRE          register DI (GetIt) + route (go_router) + l10n keys
        │
6. CODEGEN       dart run build_runner build  (only because codegen inputs changed)
        │
7. VALIDATE      dart format → flutter analyze → check_layers.sh → flutter test -r compact
```

The key efficiency trick: the **generator writes the mechanical skeleton to disk**
(printing a `FINAL` list of complete files and a `FILL` list of `TODO(you)`
files), so the agent spends tokens on real logic — not boilerplate it would
otherwise emit as model output.

### Progressive reference loading
The skill ships **27 reference docs** but **reads only the ones a task needs**. A
networking task loads `networking.md` + `api-contracts.md` + `errors-and-results.md`;
a feature task loads `feature-generation.md` + the active stack reference. Crucially
the active stack's reference **replaces** the others — a Riverpod project reads
`riverpod.md` *instead of* `bloc-cubit.md`, never both. This keeps token cost down.

---

## 5. The generators (the engine)

`scripts/new_feature.sh` is the heart of the skill. It scaffolds three feature
types, and has two contract-driven modes:

| Mode | Flag | What it produces |
|---|---|---|
| **From an OpenAPI/Swagger contract** (preferred) | `--openapi <spec> --path <endpoint> [--method <verb>]` | **Exact** types **and** the Retrofit client + Dio datasource. Full type coverage: scalars, `date-time`→`DateTime`, nested `$ref`, arrays, enums, `allOf` (merged), `additionalProperties`→`Map`, and `oneOf`/`anyOf` → a **sealed class** hierarchy with discriminator dispatch. |
| **From a sample JSON** | `--json <sample>` | The entity + model + nested types + `toEntity` mapping inferred from one response. Models default fields nullable (APIs lie); entities are non-null with fallbacks; `id` stays required; snake_case keys get `@JsonKey`. Does **not** write the Retrofit client (a sample can't give the verb/path). |

**Feature types:** `ui` (presentation-only page), `api` (full clean arch), `form`
(validated `Form` + state holder).

**Verbs:** `get` (auto-detects collection vs fetch-by-id from `{id}`);
`post|put|patch|delete` generate a **command** — and the command holder is
**Cubit-shaped across all five stacks** (intentional, not an event Bloc on the bloc
stack).

The engines themselves are `scripts/_openapi_to_dart.py` and
`scripts/_json_to_dart.py` (Python 3).

---

## 6. The five state-management stacks

Only the **presentation layer + its DI wiring** changes per stack — `domain/` and
`data/` are **identical** for all five.

| Stack | State holder | DI | Persistence | Codegen |
|---|---|---|---|---|
| **Bloc/Cubit** (default) | Cubit / Bloc | GetIt | HydratedBloc | no |
| **Riverpod** | Notifier / provider | **providers (no GetIt)** | shared_preferences | yes |
| **Provider** | ChangeNotifier | GetIt | shared_preferences | no |
| **GetX** | GetxController (presentation only) | GetIt | shared_preferences | no |
| **MobX** | Store | GetIt | shared_preferences | yes |

Notable constraints the skill documents loudly so a stack doesn't swallow the
architecture: Riverpod uses providers *as* DI (no GetIt); GetX is used for
presentation state only (GetIt for DI, go_router for routing — no `GetMaterialApp`).

---

## 7. The standard stack (packages)

Dio + Retrofit · JsonSerializable codegen · GetIt · Envied + Flutter Flavorizr ·
Easy Localization (+ `flutter_localizations`) · go_router · centralized
Material-3 theme · `flutter_screenutil_plus` · HydratedBloc · `very_good_analysis`
· bloc_test + mocktail.

Versions are **never hand-pinned** — the skill always resolves the latest
compatible version with `flutter pub add`. `package-stack.md` lists illustrative
baselines plus the known `json_annotation` / `json_serializable` resolution-conflict
playbook.

---

## 8. Quality gates & validation

The skill is "executable guarantees, not prose." After edits it runs:

```
dart format .  →  flutter analyze  →  scripts/check_layers.sh  →  flutter test -r compact
```

- **`check_layers.sh`** — fails the build (exit 1) if domain purity **or**
  presentation→data is violated.
- **`doctor.sh`** — preflight: SDK + Dart-3 floor + `pub get` health + outdated
  packages (`--docs` scans references for version drift).
- **`validate_flutter_project.sh`** — runs the whole chain (pub get → conditional
  build_runner → format → analyze → check_layers → flavor-config check → test).
  **Quiet on success** (one `✓` per step), diagnostics only on failure — so build
  noise doesn't flood context.

`build_runner` runs **only** when generated-code inputs actually changed.

---

## 9. Proven by an eval harness

`eval/run.sh` builds **23 generation scenarios** (5 stacks × GET/by-id/POST/PUT/
DELETE + OpenAPI special cases: values, shapes, oneof, altcore, riverpod-dioprov)
in throwaway Flutter projects, each checked for: **compiles** (`flutter analyze`) ·
**both layer gates** · **values map correctly** (`fromJson→toEntity` asserted) ·
**runs end-to-end** (datasource→repo→usecase→holder) · **renders** (the real page
pumps through DI + widgets + localization) — plus a **negative-input block** (5
bad-input paths must be rejected). All green on Flutter 3.41 and 3.44. This is why
the generators can be trusted, not just hoped at.

---

## 10. The guardrails (it pushes back)

- **Won't invent API models** — asks for the JSON/contract first.
- **Never leaks `DioException` to UI** — mapped to domain failures.
- **No business logic in widgets**; no hardcoded colors/text when a theme token exists.
- **Won't switch your state-management stack** or edit generated files.
- **No `bootstrap.dart` indirection** — startup goes in `main()` / a shared
  `runApplication()` in the app composition root.
- **No unnecessary packages** in an existing project.
- **Conditional codegen** — never blind-runs `build_runner`.

---

## 11. Anatomy of the skill folder

```
flutter-clean-architecture/
├── SKILL.md            ← AUTHORITATIVE agent behavior: mode detection, progressive
│                          loading map, non-negotiable rules, validation workflow.
├── README.md           ← Practical task-by-task guide (how to use it).
├── CAPABILITIES.md     ← Full "you can ask…" capability table + reference map.
├── OVERVIEW.md         ← This file: what it is & how it works.
├── CHANGELOG.md        ← Versioned release history (current: V12).
├── package.sh          ← Builds a junk-free distributable zip (scrubs build/,
│                          .DS_Store, __pycache__, .dart_tool, __MACOSX).
│
├── references/  (27 playbooks, loaded on demand)
│   ├── architecture.md            layering, dependency rules, SOLID, the 2 gates
│   ├── project-creation.md        new-project workflow + Full/Lean scope
│   ├── package-stack.md           packages + resolution-conflict playbook
│   ├── feature-generation.md      how to build a feature; fake-datasource pattern
│   ├── bloc-cubit.md              Cubit vs Bloc, concurrency, pagination, observer
│   ├── riverpod.md · provider.md · getx.md · mobx.md   per-stack (load ONE)
│   ├── api-contracts.md           never invent models; ask for JSON
│   ├── networking.md              Dio + Retrofit
│   ├── models-and-codegen.md      JsonSerializable / Freezed / build_runner
│   ├── errors-and-results.md      Result + AppFailure, Dio→failure mapping
│   ├── auth-and-secure-storage.md tokens, secure storage
│   ├── theme.md                   Material-3 colors/type/spacing, ThemeExtension
│   ├── responsive-ui.md           screenutil, cached images
│   ├── localization.md            easy_localization, RTL, persisted locale
│   ├── dependency-injection.md    GetIt registration rules
│   ├── routing.md                 go_router (redirect, refreshListenable, shells)
│   ├── env-and-flavors.md         Envied + Flavorizr (+ gotchas)
│   ├── forms.md · connectivity.md · logging.md
│   ├── testing.md                 bloc_test/mocktail + compact runner + goldens
│   ├── review-checklist.md        review criteria
│   ├── codegen-troubleshooting.md build_runner failure playbook
│   └── assets-and-codegen.md      flutter_gen, flutter_svg gotcha, fonts
│
├── scripts/  (the executable engine)
│   ├── new_feature.sh             scaffold a feature skeleton (the token-saver)
│   ├── _openapi_to_dart.py        OpenAPI→Dart engine (exact types + Retrofit)
│   ├── _json_to_dart.py           JSON→Dart engine (entity + model + mapping)
│   ├── scaffold_default_features.sh  drops the validated Full scaffold
│   ├── flavorize.sh               runs flutter_flavorizr + fixes the gotchas
│   ├── detect_stack.sh            prints the project's state-management stack
│   ├── check_layers.sh            FAILS if a layer boundary is crossed
│   ├── doctor.sh                  preflight: SDK + pub-get health + outdated
│   ├── _doctor_outdated.py        parses `pub outdated --json` for doctor.sh
│   └── validate_flutter_project.sh  the full validation chain (quiet on success)
│
├── assets/default-scaffold/   placeholderized Full-scaffold source (core/app/
│                              features/test/lang) substituted on project creation
└── eval/                      run.sh (23 scenarios + 5 negative paths) + fixtures/
```

---

## 12. Quick-start examples

```bash
# Create a project (asks directory + org + stack, then scaffolds the foundation)
/flutter-clean-architecture create flutter project shop_app

# Lean start, Riverpod
/flutter-clean-architecture create a lean flutter project shop_app, no demo or flavors, riverpod

# Add an API feature from a contract (the skill never invents models)
/flutter-clean-architecture add an elixirs feature from this swagger: <spec> path /Elixirs

# Other free-text asks it understands
add dark mode and centralize the theme
add Arabic localization + a language switcher
add token auth with secure storage and gate the routes
review this against clean architecture / SOLID
```

Under the hood a feature ask becomes:

```bash
scripts/new_feature.sh api elixirs --item elixir --openapi swagger.json --path /Elixirs
#  → Elixir (+nested) · ElixirModel · ElixirsApi (@GET) · datasource · repo
#    · use case · ElixirsCubit · ElixirsPage   (then: fill TODOs, wire DI/route/l10n, validate)
```

---

## 13. Versioning & packaging

Releases are versioned (current: **V12**, validated on Flutter 3.44.0 / Dart
3.12.0, also green on 3.41.0 / Dart 3.11.0 — see `CHANGELOG.md`). Build a clean,
junk-free distributable with `./package.sh V<n>` — **always** use this instead of
Finder's Compress, which injects a `__MACOSX/` tree. The script scrubs
`build/`, `.dart_tool/`, `.DS_Store`, `__pycache__`, and `*.pyc` before zipping.
