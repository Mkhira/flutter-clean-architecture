# Flutter Clean Architecture — Guide

**Version V12** · validated on Flutter 3.44.0 / Dart 3.12.0 (and 3.41.0 / Dart 3.11.0) · see `CHANGELOG.md`.

What this skill is, everything it does, and how to use it.

> This is the practical guide. `CAPABILITIES.md` is the full capability map;
> `SKILL.md` + `references/` are the authoritative behavior the agent follows.

---

## 1. What it is

An opinionated **architecture-and-codegen skill** that makes the agent build
Flutter apps like a careful senior engineer: every feature comes out layered,
type-safe, lint-clean, and tested instead of ad-hoc. It enforces **feature-first
Clean Architecture**, generates real Dart from API contracts, and guards the
layer boundaries with executable gates.

```
lib/
├── core/        DI · theme · localization · router · network · error · env
├── app/         App widget + runApplication() startup
└── features/<feature>/
    ├── domain/        entities · repository contracts · use cases   (pure Dart)
    ├── data/          models · datasources · repository impls
    └── presentation/  bloc|cubit|notifier|controller|store · pages · widgets
```

**Dependency rule (the point):** UI renders, state coordinates, domain holds
application logic, data talks to the outside world, and **infrastructure errors
never leak into widgets**. `domain/` is pure Dart — no Flutter/Dio/GetIt.

**Standard stack:** Dio + Retrofit · JsonSerializable codegen · GetIt · Envied +
Flutter Flavorizr · Easy Localization · go_router · centralized theme ·
very_good_analysis · bloc_test + mocktail. (Exact, latest-compatible versions are
resolved by `flutter pub add` — the skill never hand-pins.)

**Five state-management stacks** — Bloc/Cubit (default) · Riverpod · Provider ·
GetX · MobX. The chosen stack only changes the **presentation + DI wiring**;
domain and data layers are identical for all five. In an existing project the
skill **detects** your stack and never imposes Bloc.

---

## 2. How it works

### Triggers
- **Slash command:** `/flutter-clean-architecture <what you want>` (free text).
- **Automatic:** any Flutter/Dart task in a Flutter repo activates it — even
  without saying "clean architecture".

### Two modes (auto-detected)
- **New Project** — you ask to create an app by name → it asks for name +
  directory (+ org), offers **Full** or **Lean** scope, asks the stack, scaffolds.
- **Existing Project** — a `pubspec.yaml` exists → it inspects your conventions,
  detects your state-management stack, and follows them.

### Progressive reference loading (why it's not wasteful)
The skill ships ~27 reference docs but **reads only the ones a task needs** — a
networking task loads `networking.md` + `api-contracts.md` +
`errors-and-results.md`, not the whole set; the active stack's reference
*replaces* the others. That keeps token cost down.

### Helper scripts (`scripts/`)
| Script | Does |
|---|---|
| `new_feature.sh <ui\|api\|form> <name> [--item <s>] [--stack <s>] [--json <f> \| --openapi <spec> --path <p> --method <verb>]` | scaffolds a feature on disk (the token-saver) |
| `_openapi_to_dart.py` | the OpenAPI→Dart engine `--openapi` uses (exact types + **Retrofit client** + datasource) |
| `_json_to_dart.py` | the JSON→Dart engine `--json` uses (entity + model + nested + mapping) |
| `detect_stack.sh` | prints `bloc\|riverpod\|provider\|getx\|mobx\|unknown` for the project |
| `check_layers.sh [lib]` | **fails** if a boundary is crossed (see §5) |
| `doctor.sh [--docs]` | preflight: SDK + Dart-3 floor + `pub get` health + outdated packages; `--docs` scans references for version drift |
| `validate_flutter_project.sh` | pub get → codegen → format → analyze → check_layers → `flutter test` — **quiet on success**, diagnostics only on failure |
| `package.sh [version]` | builds a junk-free distributable zip (`./package.sh V1`) |

---

## 3. The generators (the engine)

`new_feature.sh` scaffolds the mechanical skeleton so the agent spends tokens on
real logic, not boilerplate. Three feature types:

- **`ui`** — presentation-only page (no domain/data — nothing to abstract).
- **`api`** — full clean arch: domain (entity/repo/use case) + data
  (model/datasource/repo impl, error→failure) + presentation (per stack).
- **`form`** — a validated `Form` page + state holder, wire a use case into submit.

After scaffolding it prints **FINAL** (complete files — don't open them) and
**FILL** (files with a `TODO(you)` — open only these), plus exact DI / route /
l10n follow-ups, and refuses to overwrite an existing feature.

### `--json <sample>` — infer the data shape from a sample response
Generates the **entity + model + nested types + `toEntity` mapping** from one
JSON sample. Models default every field nullable (APIs lie); entities are
non-null with fallbacks; `id` stays required; snake_case keys get `@JsonKey`. It
does **not** write the Retrofit client (a sample can't give the verb/path).

### `--openapi <spec> --path <endpoint> [--method <verb>]` — generate from a contract (preferred)
The spec is a contract, so the generator emits **exact** types **and** the
Retrofit client + Dio-backed datasource. Full type coverage:

- scalars (`int`/`double`/`bool`/`String`), `format: date-time` → `DateTime`
- nested `$ref` objects, arrays, enums → `String`, real `nullable`
- **`allOf`** composition (merged), **`additionalProperties`** → `Map<String,V>`
- **`oneOf`/`anyOf` polymorphism** → a **sealed class** hierarchy with
  discriminator `fromJson` dispatch and common fields lifted to the base

**Verbs:**
- `get` (default) — auto-detects **collection** (array → list screen + query
  filters) or **fetch-by-id** (`{id}` → detail screen).
- `post|put|patch|delete` — a **command**: request entity/model (`toJson` +
  `fromEntity`), verb-correct Retrofit client, `submit`/`update`/`delete` chain,
  and a command holder. Generated for **all five stacks**.

> **Note:** a command feature's holder is intentionally **Cubit-shaped across
> all five stacks** — even on the bloc stack it emits a command holder, not an
> event-driven Bloc. This is deliberate, not an incomplete generator.

For **Riverpod**, the generated datasource provider auto-wires your project's
`dioProvider` when one exists (else a bare `Dio()` with a warning).

---

## 4. How to use it

### A. Create a project
```
/flutter-clean-architecture create flutter project shop_app
```
It asks for directory + org + stack, then scaffolds the full foundation. Minimal:
```
/flutter-clean-architecture create a lean flutter project shop_app, no demo or flavors, riverpod
```

### B. Add an API feature (the main workflow)
Describe it and give the contract — the skill **never invents models**:
```
/flutter-clean-architecture add an elixirs feature from this swagger: <spec> path /Elixirs
```
Under the hood:
```bash
# exact types + Retrofit client + datasource straight from the contract
scripts/new_feature.sh api elixirs --item elixir --openapi swagger.json --path /Elixirs
#  -> Elixir (+ nested) · ElixirModel · ElixirsApi (@GET) · datasource · repo · use case · ElixirsCubit · ElixirsPage
```
Or from a sample JSON (no spec):
```bash
scripts/new_feature.sh api houses --item house --json houses.json
```
- `--item house` → singular entity/model while collection types stay plural.
- Then the agent fills only what's left (the FILL list), wires DI + route + l10n,
  and validates.

### C. UI-only, form, or command features
```bash
scripts/new_feature.sh ui about                                  # presentation-only page
scripts/new_feature.sh form contact                              # Cubit + validated Form
scripts/new_feature.sh api feedback --openapi s.json --path /Feedback --method post   # a command
```

### D. Other common asks (free text)
```
add dark mode and centralize the theme
add Arabic localization + a language switcher
add token auth with secure storage and gate the routes
add a logger / offline detection / type-safe assets
review this against clean architecture / SOLID
add golden tests for the cards
```

### E. Validate (after edits)
```bash
scripts/validate_flutter_project.sh        # one ✓ per step; diagnostics only on failure
# or individually:
dart format . && flutter analyze
scripts/check_layers.sh
flutter test -r compact
dart run build_runner build --delete-conflicting-outputs   # only if codegen inputs changed
```

---

## 5. Guarantees (executable gates, not prose)

`check_layers.sh` enforces **two** boundaries and fails the build if either is crossed:
1. **Domain purity** — no `domain/` file imports Flutter/Dio/Retrofit/GetIt/etc.
2. **Presentation → data** — no `presentation/` file imports a feature's `data/`
   layer (the one exception: a Riverpod `@riverpod` composition file).

Plus the non-negotiables the agent pushes back on:
- Won't invent API models — asks for the JSON/contract.
- Never leaks `DioException` to UI (mapped to domain failures).
- No business logic in widgets; no hardcoded colors when a theme token exists.
- Won't switch your state-management stack or edit generated files.
- Runs `build_runner` only when generated-code inputs changed.

### SDK awareness
Generated code uses Dart 3 features (sealed classes, switch-expression patterns).
`new_feature.sh` and `doctor.sh` **detect** the installed Dart and your
project's `environment: sdk:` constraint and **warn** if either is below the
Dart 3.0 floor — so a scaffold never silently lands code your SDK can't compile.

---

## 6. Token tips
- `new_feature.sh` (esp. `--openapi`) shaves the biggest chunk — it writes the
  boilerplate + exact types on disk instead of as model output, and prints the
  **FINAL list so generated files are never re-opened** (`grep -rln 'TODO(you)'
  lib/features/<name>` finds the rest).
- Validation is **quiet on success** — build noise no longer floods context.
- A **full new project** ≈ 100–140k tokens; **Lean** ≈ half; **one API feature**
  is much less. Keep tests `-r compact` and scoped to the changed file.

---

## 7. Versioning & packaging
- Releases are versioned (this is **V12**); `CHANGELOG.md` records the Flutter
  version targeted and what changed.
- Build a clean, junk-free distributable with `./package.sh V<n>` (scrubs
  `.DS_Store`/`__pycache__`/`build`; never use Finder's Compress).
- A hardened post-release maintenance template lives at
  `../flutter-skill-maintenance.md` (audits the skill against a new Flutter
  stable using a *sandboxed* SDK — never upgrades your global toolchain).

---

## 8. Example features built with this skill

| Feature | Source | Notable |
|---|---|---|
| products | fake datasource | paginated Bloc, infinite scroll + pull-to-refresh |
| elixirs | Wizard World API | nested ingredients/inventors, difficulty filter |
| houses | Wizard World API | nested heads/traits, house-colored Hero avatars |
| auth | fake | secure-storage tokens, auth-gated routing (redirect + refreshListenable) |

Each is the same shape: `new_feature.sh` → fill the FILL list → DI + route + l10n
→ `check_layers` + analyze + `flutter test`.
