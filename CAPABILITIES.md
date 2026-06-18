# Flutter Clean Architecture — Capabilities

What this skill can do, how to invoke it, and where each capability is defined.

> This is a **reference/overview** document. The skill is driven by natural-language
> intent, not fixed sub-commands — you describe what you want and it routes to the
> right playbook. The authoritative behavior lives in `SKILL.md` and `references/`.

---

## What it is

An opinionated, practical Flutter **Clean Architecture** skill that makes the agent
behave like a careful senior Flutter engineer. It enforces feature-first layering
(presentation / domain / data per feature, with shared `core/`), keeps
infrastructure errors out of the UI, and applies SOLID where boundaries earn their
keep — not architecture theater.

**Standard stack:** Bloc/Cubit · Dio + Retrofit · JsonSerializable (codegen) ·
GetIt · Envied + Flutter Flavorizr · Easy Localization (+ `flutter_localizations`) ·
centralized theme/design-system · `flutter_screenutil_plus` · go_router ·
HydratedBloc · `very_good_analysis` · bloc_test + mocktail.

---

## How to invoke

- **Explicit:** `/flutter-clean-architecture <what you want>` — the argument is
  free text describing intent (e.g. `create flutter project shop_app`).
- **Automatic:** triggers on its own whenever you're working in a Flutter project
  and the task involves implementation, API integration, models, Bloc/Cubit, UI,
  theming, localization, DI, networking, tests, or review — even without the words
  "clean architecture".

### Two modes (auto-detected)

| Mode | When | Behavior |
|---|---|---|
| **New Project** | You ask to create a Flutter app by name | Asks for name + directory (and optionally `--org`), then scaffolds per `references/project-creation.md`. |
| **Existing Project** | A `pubspec.yaml` with Flutter exists, or you mention Flutter work | Inspects current conventions first and follows them; this skill's defaults yield to a consistent existing convention. |

### New-project scaffold scope

| Scope | Trigger | What you get |
|---|---|---|
| **Full** (default) | "create flutter project X" | Full scaffold: products + settings demo features, multi-flavor Envied + Flutter Flavorizr, full test suite. Production-shaped foundation. |
| **Lean** | "minimal", "lean", "quick start", "barebones", "no demo feature/flavors" | `core/` + `app/` + a single minimal home screen, single `main.dart` + one env (no flavorizr), only the packages that minimal set needs. |

---

## Capability surface

Each row is something you can ask for in plain language. The "Playbook" column is
the reference file that defines how it's done.

### Project creation
| You can ask… | Example | Playbook |
|---|---|---|
| Create a new project (Full) | `create flutter project shop_app` | `project-creation.md` |
| Create a new project (Lean) | `create a minimal flutter project, no flavors` | `project-creation.md` |
| Set org / directory | `…in ~/dev with org com.acme` | `project-creation.md` |
| Choose packages | (handled automatically) | `package-stack.md` |

### Features & layers
| You can ask… | Example | Playbook |
|---|---|---|
| API-backed feature | `add an orders feature from this API <json>` | `feature-generation.md`, `architecture.md` |
| UI-only feature | `add an About page` | `feature-generation.md` |
| Local-state feature | `add a counter cubit screen` | `bloc-cubit.md` |
| Persisted state | `persist the selected theme/locale/filter` | `bloc-cubit.md` |
| Form-heavy feature | `build a login form with validation` | `forms.md` |
| Refactor a layer | `extract URL building into a mapper` | `architecture.md` |
| Fake/in-memory datasource | `wire a fake datasource so it runs with no backend` | `feature-generation.md` |

### Networking & data
| You can ask… | Example | Playbook |
|---|---|---|
| Retrofit API client | `add a Retrofit client for /orders` | `networking.md` |
| Response/request models | `create the models for this JSON` | `models-and-codegen.md`, `api-contracts.md` |
| Error → failure mapping | `map Dio errors to domain failures` | `errors-and-results.md` |
| Result/Either types | `return a Result instead of throwing` | `errors-and-results.md` |
| Run codegen | `run build_runner` | `models-and-codegen.md` |

### State management
| You can ask… | Example | Playbook |
|---|---|---|
| Cubit for simple state | `add a Cubit for this toggle` | `bloc-cubit.md` |
| Bloc for event-heavy flows | `convert this to a Bloc with events` | `bloc-cubit.md` |
| Pagination | `add infinite scroll with droppable` | `bloc-cubit.md` |
| Pull-to-refresh | `add pull-to-refresh (restartable)` | `bloc-cubit.md` |
| App-level observer | `add a BlocObserver` | `bloc-cubit.md` |

### Cross-cutting concerns
| You can ask… | Example | Playbook |
|---|---|---|
| Auth / tokens | `store the auth token securely` | `auth-and-secure-storage.md` |
| Theme / design system | `centralize colors & text styles`, `add dark mode` | `theme.md` |
| Responsive UI | `make this grid responsive` | `responsive-ui.md` |
| Localization | `add Arabic + a language switcher` | `localization.md` |
| Dependency injection | `register this chain in GetIt` | `dependency-injection.md` |
| Routing | `add a route for the detail screen` | `routing.md` |
| Env & flavors | `set up dev/staging/prod with Envied` | `env-and-flavors.md` |
| Connectivity | `add offline detection` | `connectivity.md` |
| Logging | `add a logger (no secrets)` | `logging.md` |
| Assets / SVG / fonts | `add type-safe assets`, `render this SVG icon` | `assets-and-codegen.md` |

### Quality
| You can ask… | Example | Playbook |
|---|---|---|
| Code review | `review this against clean architecture / SOLID` | `review-checklist.md` |
| Validation | `run analyze and tests` | `testing.md` |
| Write tests | `add bloc_test + repository tests` | `testing.md` |
| Golden tests | `add golden tests for the cards` | `testing.md` |
| Integration tests | `add an end-to-end login flow test` | `testing.md` |
| Fix a bug | `fix the duplicate Hero tag crash` | (relevant playbook) |

---

## Guardrails (it will push back)

- **No invented API models** — it asks for the JSON/contract first.
- **No `DioException` in the UI** — errors are mapped to domain failures.
- **No business logic in widgets** — widgets render; Cubit/Bloc coordinates.
- **No hardcoded colors/text styles** when a theme token exists.
- **No new state-management package** — Bloc/Cubit unless the project clearly uses
  another pattern.
- **No editing generated files** (`*.g.dart`, `*.freezed.dart`).
- **No `bootstrap.dart`** — startup goes in `main()` / a shared `runApplication()`.
- **No unnecessary packages** in an existing project.
- **Conditional codegen** — `build_runner` runs only when generated-code inputs
  changed.

---

## Validation workflow

After edits the skill runs: `dart format .` → `flutter analyze` →
`flutter test -r compact <scoped path>` (compact reporter, scoped to what
changed; full suite only as a final pass) → conditional `build_runner`.
A `scripts/validate_flutter_project.sh` helper runs the whole chain.

---

## Reference map

`SKILL.md` loads only what a task needs. The playbooks:

```
architecture.md            layering, dependency rules, SOLID mapping
project-creation.md        new-project workflow + Full/Lean scope
package-stack.md           packages + resolution-conflict troubleshooting
feature-generation.md      how to build a feature; fake datasource pattern
bloc-cubit.md              Cubit vs Bloc, concurrency, pagination, observer
riverpod.md / provider.md / getx.md / mobx.md
                           per-stack presentation + DI + tests (load ONE,
                           instead of bloc-cubit.md, for the active stack)
api-contracts.md           never invent models; ask for JSON
networking.md              Dio + Retrofit
models-and-codegen.md      JsonSerializable / Freezed / build_runner
errors-and-results.md      Result + AppFailure, Dio→failure mapper
auth-and-secure-storage.md tokens, secure storage
theme.md                   colors/typography/spacing, ThemeExtension, dark mode
responsive-ui.md           screenutil, cached images
localization.md            easy_localization, RTL, persisted locale
dependency-injection.md    GetIt registration rules
routing.md                 go_router
env-and-flavors.md         Envied + Flavorizr (+ gotchas)
forms.md                   formz / validation
connectivity.md            online/offline
logging.md                 logger usage
testing.md                 bloc_test/mocktail + compact runner + golden/integration
review-checklist.md        review criteria
codegen-troubleshooting.md build_runner failure playbook
assets-and-codegen.md      flutter_gen, flutter_svg gotcha, resolution, fonts
```

Helper scripts under `scripts/`:

```
new_feature.sh <ui|api|form> <name> [--item <singular>]
               [--json <file> | --openapi <spec> --path <endpoint>]
               [--stack <bloc|riverpod|provider|getx|mobx>]
                                       scaffold a feature skeleton (token-saver);
                                       --item keeps the entity/model singular;
                                       --json infers entity+model from a sample;
                                       --openapi generates exact types + the
                                       Retrofit client from a spec contract;
                                       --stack branches the presentation layer
_json_to_dart.py                       JSON→Dart engine used by --json (python3)
_openapi_to_dart.py                    OpenAPI→Dart engine used by --openapi
                                       (entity+model+nested + Retrofit client)
check_layers.sh [lib]                  fail if domain/ imports framework/infra
doctor.sh [--docs]                     preflight: SDK + pub get health + outdated
                                       key packages; --docs scans refs for drift
_doctor_outdated.py                    parses `pub outdated --json` for doctor.sh
validate_flutter_project.sh            pub get → codegen → format → analyze →
                                       check_layers → flutter test -r compact
```

---

## Token cost (rough)

The harness bills the whole conversation, but as a guide:

- **Full new project** ≈ 100–140k tokens (≈24k references + generated code +
  validation output).
- **One feature/layer** ≈ 40–60k tokens (less if references are already loaded
  in-session and you skip on-device runs). `scripts/new_feature.sh` shaves
  ~25–35% off an API feature by scaffolding the boilerplate on disk instead of
  emitting it as output tokens.
- **Lean new project** ≈ roughly half of Full.
- Biggest avoidable costs: full `flutter test` output (use `-r compact`),
  on-device `flutter run` + screenshots, and dependency-resolution iterations.
