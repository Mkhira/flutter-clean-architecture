# Flutter Clean Architecture

A skill that helps you build Flutter apps the right way — every feature comes out
**layered, type-safe, lint-clean, and tested** instead of ad-hoc. It follows
**feature-first Clean Architecture** and keeps your code organized as the app grows.

---

## Project structure

```
lib/
├── core/        DI · theme · localization · router · network · error · env
├── app/         App widget + startup
└── features/<feature>/
    ├── domain/        entities · repository contracts · use cases   (pure Dart)
    ├── data/          models · datasources · repository implementations
    └── presentation/  state management · pages · widgets
```

**The rule:** UI renders, state coordinates, domain holds the logic, and data
talks to the outside world. Network/infrastructure errors never leak into your
widgets, and `domain/` stays pure Dart.

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
