# Project Creation

Use this guide in New Project Mode, after the project name and directory are
known.

> **Lean mode.** This guide describes the **Full** scaffold. If the user asked
> for a minimal/lean/quick start (see "Scaffold scope" in `SKILL.md`), trim it:
> keep steps 1–7 and the `core/`/`app/` setup, scaffold a single minimal home
> screen instead of the products + settings features, and **skip flavors**
> entirely (single `main.dart` + one `.env` or `--dart-define` — skip
> flavorizr, the per-flavor Env classes, and steps tied to them). Add only the
> packages that minimal set needs.

## Fast path: scaffold the default features instead of hand-emitting them

The **Full** scaffold's core/, app/, products, and settings code is mechanical
and identical every time except for the package name — hand-emitting it costs
~100k tokens. Drop the validated, analyze-clean template instead and spend
tokens only on project-specific customization:

```bash
flutter create --org <org> <project_name>
cd <project_name>
scripts/scaffold_default_features.sh .   # writes core/app/products/settings + tests + l10n + .env.*
```

It substitutes the package name, removes the demo `widget_test.dart`, and prints
the exact follow-ups: add the package set (step 5 below / `package-stack.md`),
wire `assets/lang` + iOS `CFBundleLocalizations`, run build_runner, author
`flavorizr.yaml` then `scripts/flavorize.sh`, and finally **`dart fix --apply`**
(REQUIRED — own-package `package:<name>/...` imports sort to a name-dependent
position, so without it `directives_ordering` flags). Then
`scripts/validate_flutter_project.sh`. The manual steps below remain the
reference for what each generated file does and for Lean mode (which the script
does not cover — scaffold a single minimal home screen by hand instead).

## Workflow

1. Ask for project name and directory if missing. Optionally confirm `--org`.
2. Check Flutter is installed, and surface the SDK (packages resolve against it):

   ```bash
   flutter --version    # Flutter + Dart version
   ```

   Then ask **once** which state-management stack (default **Bloc/Cubit** if no
   answer / non-interactive): `1. Bloc/Cubit  2. Riverpod  3. Provider  4. GetX
   5. MobX`. The stack changes only presentation + DI wiring; domain/data are
   identical. Load only that stack's reference (`bloc-cubit.md` default, else
   `riverpod.md`/`provider.md`/`getx.md`/`mobx.md`).

3. Create the project inside the requested directory:

   ```bash
   flutter create --org com.example <project_name>
   ```

   Adjust `--org` to the value confirmed with the user; it determines the Android
   `applicationId` and iOS `bundleId` later used by flavors.

4. Enter the project directory.
5. Add packages using latest compatible versions (`flutter pub add ...` /
   `flutter pub add dev:...`). Add the **base set + the chosen stack's set** —
   see the "State-management stacks" table in `package-stack.md` (Riverpod adds
   no `get_it`; non-Bloc stacks add `shared_preferences` for persistence).
6. Create the folder structure.
7. Create `analysis_options.yaml`. Use `very_good_analysis` with a few rule
   overrides that are app-appropriate (vs. published-package defaults) and that
   reconcile with Clean Architecture:

   ```yaml
   include: package:very_good_analysis/analysis_options.yaml

   analyzer:
     exclude:
       - "**/*.g.dart"
       - "**/*.freezed.dart"
       - "lib/flavors.dart"

   linter:
     rules:
       # Application, not a published package — dartdoc on every public member
       # is noise.
       public_member_api_docs: false
       # Dependencies are grouped by concern, not alphabetized.
       sort_pub_dependencies: false
       # Clean Architecture repository/datasource contracts are intentional
       # boundaries that often start with a single method and grow — they are
       # not a stand-in for a function typedef.
       one_member_abstracts: false
   ```

   Use `flutter_lints` instead if `very_good_analysis` is too strict for the
   project or the SDK does not support it:

   ```yaml
   include: package:flutter_lints/flutter.yaml
   ```

8. Configure localization, theme, flavors/env, DI, networking, router, Bloc
   observer, HydratedBloc storage, and tests (see the relevant reference files).
   Create the default **products** feature — the full Clean Architecture example
   (data / domain / presentation) described in `architecture.md` and
   `feature-generation.md`. It is a **paginated, infinite-scroll list using
   Bloc** (page size 10): the page listens to a `ScrollController` and dispatches
   a `droppable()` `ProductsFetched` event on the rising edge of reaching the
   bottom (not continuously), appending pages until `hasReachedMax`, plus
   pull-to-refresh via a `RefreshIndicator` + `restartable()` `ProductsRefreshed`
   event (see `bloc-cubit.md`). So the app loads and displays data on
   first run **without a real backend**, register a **fake datasource** that
   serves seeded, paginated products behind the `ProductsRemoteDataSource`
   contract (the DIP payoff: swap the fake for the Retrofit-backed impl in one DI
   line once the API exists). Point the `/` route at `ProductsPage`, register the
   products chain in DI (with `ProductsBloc` as a factory), and add the
   `products.*` keys to both `en.json`/`ar.json`. See `feature-generation.md` for
   the fake-datasource pattern. Also create a **settings** feature: a
   `SettingsBloc` (HydratedBloc) whose serializable `SettingsState` persists the
   selected locale **and theme mode**, with a change-language button (wired via
   `startLocale`/`saveLocale: false` + a root `BlocListener` — see
   `localization.md`) and a theme toggle (drives `MaterialApp.themeMode` via a
   `BlocBuilder` — see `theme.md`).
9. Replace the default `test/widget_test.dart`. `flutter create` scaffolds it
   against the demo `MyApp` widget, which you removed — left as-is it breaks
   `flutter analyze`/`flutter test`. Delete it or replace it with a real test
   (see `testing.md`).
10. Run validation (`scripts/validate_flutter_project.sh`).

## Required new-project folders

```text
assets/
└── lang/
    ├── en.json
    └── ar.json

lib/
├── main.dart
├── app/
├── core/
└── features/
    └── products/                    # default landing feature (full clean arch)
        ├── data/
        │   ├── api/products_api_client.dart
        │   ├── datasources/
        │   │   ├── products_remote_data_source.dart       # contract + Retrofit impl
        │   │   └── products_fake_remote_data_source.dart  # seeded, paginated data
        │   ├── models/
        │   │   ├── products_page_model.dart               # page envelope: {items, page, pageSize, total, totalPages}
        │   │   ├── product_model.dart
        │   │   └── product_category_model.dart
        │   └── repositories/products_repository_impl.dart
        ├── domain/
        │   ├── entities/product.dart
        │   ├── entities/product_category.dart
        │   ├── entities/paginated_products.dart
        │   ├── repositories/products_repository.dart
        │   └── usecases/get_products_use_case.dart
        └── presentation/
            ├── bloc/
            │   ├── products_bloc.dart
            │   ├── products_event.dart
            │   └── products_state.dart
            ├── pages/products_page.dart        # infinite scroll
            └── widgets/product_card.dart
    └── settings/                    # persisted app settings (locale, theme)
        └── presentation/
            ├── bloc/
            │   ├── settings_bloc.dart          # HydratedBloc
            │   ├── settings_event.dart
            │   └── settings_state.dart         # serializable settings model
            └── widgets/
                ├── language_toggle_button.dart
                └── theme_mode_toggle_button.dart

test/
├── core/
└── features/
    ├── products/
    │   ├── data/products_repository_impl_test.dart
    │   └── presentation/products_bloc_test.dart
    └── settings/presentation/settings_bloc_test.dart
```

Localization assets live in the **project root** `assets/` scope, not inside
`lib`. Do not create a `bootstrap/` folder.

The default landing page is a **products** feature — the canonical full Clean
Architecture example (presentation → domain → data). It replaces the demo
`MyApp` counter from `flutter create` and doubles as the template users copy.
It is a **paginated, infinite-scroll list built with Bloc** (not Cubit), because
the flow is event-driven and needs `droppable()` to avoid overlapping fetches —
see `bloc-cubit.md`. A **fake datasource** (seeded, paginated sample data) is
wired by default so the screen displays real-looking products with no backend
and real pages to scroll; swap it for the Retrofit-backed
`ProductsRemoteDataSourceImpl` in one DI line when the API is ready. The minimal
local-state **counter** Cubit remains documented in `bloc-cubit.md` as the
smallest possible example.

## Default flavors and env files

Flavors:

```text
dev
staging
prod
```

Env files:

```text
.env.dev
.env.staging
.env.prod
```

Add `.env*`, generated Envied files, and any sensitive generated env files to
`.gitignore` as appropriate. See `env-and-flavors.md`.

## Sample startup flow

Single-entrypoint projects put startup directly in `main()` in `main.dart` —
this is Flutter's convention. Do **not** introduce a `bootstrap.dart`.

> **`kIsWeb` needs a foundation import.** This startup body uses `kIsWeb`, which
> lives in `package:flutter/foundation.dart`. When the body sits in
> `app/app.dart` (which imports `material.dart`), `kIsWeb` is **not** in scope and
> `flutter analyze` fails with `undefined_identifier`. Add
> `import 'package:flutter/foundation.dart';` to whichever file holds this code.

```dart
import 'package:flutter/foundation.dart'; // kIsWeb

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory((await getApplicationDocumentsDirectory()).path),
  );

  Bloc.observer = const AppBlocObserver();

  await configureDependencies();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
      ],
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      child: const App(),
    ),
  );
}
```

For **multi-flavor** projects, the per-flavor `main_<flavor>.dart` files each set
`Env` then call one shared startup function. Move the body above into a
top-level `Future<void> runApplication() async { ... }` in `app/app.dart`
(alongside the `App` widget), and have each entrypoint do:

```dart
import 'dart:async';

void main() {
  Env.baseUrl = EnvDev.baseUrl; // EnvStaging / EnvProd in the other files
  unawaited(runApplication());
}
```

Name it `runApplication()` (or similar) — never `bootstrap()`. See
`env-and-flavors.md`.

If exact APIs change, adapt to the installed package version. The
`HydratedStorage.build` / `HydratedStorageDirectory` API has shifted across
hydrated_bloc majors — verify against the installed version before copying.

## New project checklist

- `pubspec.yaml` has dependencies and assets.
- `analysis_options.yaml` exists with an `include:` line.
- `assets/lang/en.json` exists.
- `assets/lang/ar.json` exists.
- `lib/app/app.dart` exists.
- `lib/app/app_bloc_observer.dart` exists.
- `lib/core/di/` exists.
- `lib/core/network/` exists.
- `lib/core/env/` exists.
- `lib/core/router/` exists.
- `lib/core/theme/` exists.
- `lib/features/` exists.
- `lib/features/products/` has `data/`, `domain/`, and `presentation/bloc/`
  layers, including `domain/entities/paginated_products.dart`.
- a **fake datasource** is registered for `ProductsRemoteDataSource` so the app
  displays paginated sample products with no backend.
- `ProductsBloc` (factory) and the products chain are registered in DI; the `/`
  route renders `ProductsPage`, which paginates on scroll (rising-edge
  `droppable()`) and supports pull-to-refresh (`RefreshIndicator` +
  `restartable()`).
- `products.*` keys exist in both `assets/lang/en.json` and `assets/lang/ar.json`.
- a `ProductsBloc` test exists (mocking the use case, covering append +
  `hasReachedMax` + refresh — see `testing.md`).
- a **settings** feature persists the locale **and theme mode** in a
  `SettingsBloc` (HydratedBloc) with a serializable `SettingsState`, exposes a
  change-language button (`startLocale` + `saveLocale: false` + root
  `BlocListener`) and a theme toggle (drives `MaterialApp.themeMode`).
- a `SettingsBloc` test exists (stubbing `Storage`, covering locale + theme mode
  persistence — see `testing.md`).
- validation passes.
