# Flutter Clean Architecture

A skill that helps you build Flutter apps the right way — every feature comes out
**layered, type-safe, lint-clean, and tested** instead of ad-hoc. It follows
**feature-first Clean Architecture** and keeps your code organized as the app grows.

---

## Project structure

The project is **feature-first**: shared foundations live in `core/`, the app
boots from `app/`, and each feature is a self-contained folder split into three
layers.

```
lib/
├── core/        shared foundations used across the whole app
│   ├── di/             dependency injection setup
│   ├── theme/          colors, text styles, design tokens (light/dark)
│   ├── localization/   languages & translations
│   ├── router/         app routes and navigation
│   ├── network/        Dio client + interceptors
│   ├── error/          failures and error mapping
│   └── env/            environment config (dev / staging / prod)
│
├── app/         the root App widget and startup
│
└── features/<feature>/
    ├── domain/        entities · repository contracts · use cases   (pure Dart)
    ├── data/          models · datasources · repository implementations
    └── presentation/  state management · pages · widgets
```

### The three layers of a feature

- **domain** — the heart of the feature. Holds the business **entities**,
  abstract **repository contracts**, and **use cases** (one action each). It's
  **pure Dart** — no Flutter, no Dio, no packages — so it never breaks when the
  outside world changes.
- **data** — talks to the outside world. **Models** parse JSON, **datasources**
  call the API (or local storage), and **repository implementations** fulfill the
  contracts the domain defines, mapping raw errors into clean domain failures.
- **presentation** — what the user sees. **State management** (Bloc, Riverpod,
  etc.) coordinates, **pages** lay out screens, and **widgets** render.

### How the layers depend on each other

```
presentation  ──▶  domain  ◀──  data
```

Both `presentation` and `data` depend on `domain` — never the reverse, and
`presentation` never reaches into `data` directly. The result: **UI renders,
state coordinates, domain holds the logic, and data talks to the outside world.**
Network and infrastructure errors never leak into your widgets, and `domain/`
stays pure Dart.

---

## What it supports

- **Five state-management stacks** — Bloc/Cubit (default), Riverpod, Provider,
  GetX, MobX. Only the presentation layer changes between them; domain and data
  stay the same.
- **API features from a contract** — give it a Swagger/OpenAPI spec or a sample
  JSON and it generates the entities, models, and networking for you. It never
  invents API models.
- **Networking** — Dio + Retrofit with proper error mapping.
- **Theming** — centralized light/dark theme and design tokens.
- **Localization** — multi-language support (e.g. Arabic + a language switcher).
- **Routing** — go_router with auth-gated routes.
- **Auth** — token auth with secure storage.
- **Flavors & environments** — dev / staging / prod.
- **Tests** — unit, bloc, and golden tests.

---

## Create a new project

Just describe what you want:

```
/flutter-clean-architecture create flutter project shop_app
```

Steps it walks you through:

1. **Name & location** — it asks for the project name, directory, and org.
2. **Scope** — choose **Full** (demo feature + flavors + everything wired) or
   **Lean** (minimal foundation).
3. **State management** — pick your stack (Bloc, Riverpod, Provider, GetX, MobX).
4. **Scaffold** — it builds the foundation, wires everything, and validates it.

Minimal example:

```
/flutter-clean-architecture create a lean flutter project shop_app, no flavors, riverpod
```

---

## Use it in an existing project

Open your Flutter project and just ask — the skill activates automatically on any
Flutter/Dart task. It **inspects your conventions and detects your stack**, so it
follows your setup instead of imposing its own.

Common requests:

```
add an elixirs feature from this swagger: <spec> path /Elixirs
add a products feature from this sample JSON
add dark mode and centralize the theme
add Arabic localization + a language switcher
add token auth with secure storage and gate the routes
review this against clean architecture / SOLID
add golden tests for the cards
```

---

## What it's useful for

- Starting a new Flutter app with a clean, scalable foundation from day one.
- Adding new features fast without breaking the architecture.
- Turning an API contract straight into working, type-safe Dart code.
- Keeping a growing codebase consistent — same shape for every feature.
- Bringing structure and best practices to an existing project.
