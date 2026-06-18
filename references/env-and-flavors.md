# Env and Flavors (Envied + Flutter Flavorizr)

## Flavors and env files

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

## Envied: one Env class per flavor

Envied binds **one file per class at compile time**. To support multiple
flavors, create one Env class per flavor and select the right one per flavor
entrypoint.

```dart
// core/env/env_dev.dart
import 'package:envied/envied.dart';

part 'env_dev.g.dart';

@Envied(path: '.env.dev')
abstract class EnvDev {
  @EnviedField(varName: 'BASE_URL')
  static const String baseUrl = _EnvDev.baseUrl;
}
```

```dart
// core/env/env_prod.dart
import 'package:envied/envied.dart';

part 'env_prod.g.dart';

@Envied(path: '.env.prod')
abstract class EnvProd {
  @EnviedField(varName: 'BASE_URL')
  static const String baseUrl = _EnvProd.baseUrl;
}
```

Expose a single accessor the rest of the app reads, populated per entrypoint:

```dart
// core/env/env.dart
abstract class Env {
  static late final String baseUrl;
}
```

```dart
// lib/main_dev.dart  (Flavorizr generates main_<flavor>.dart entrypoints)
import 'dart:async';

void main() {
  Env.baseUrl = EnvDev.baseUrl;
  unawaited(runApplication());
}
```

`runApplication()` is the single shared startup function (binding init,
HydratedBloc storage, Bloc observer, DI, `runApp`). Define it in the app
composition root — `app/app.dart`, alongside the `App` widget — so every flavor
entrypoint shares one startup path. **Do not** call it `bootstrap()` or put it
in a `bootstrap.dart`; that is not a Flutter convention (see `architecture.md`).

**Alternative:** a single `Env` class plus `--dart-define=FLAVOR=dev` is
acceptable when you do not need per-flavor compile-time obfuscation. Document
whichever approach the project uses.

## Rules

- Add `.env*` to `.gitignore` unless using safe indirection.
- Add generated env files to `.gitignore` when they contain secrets.
- Use `obfuscate: true` only as obfuscation, not real security.
- Do not treat Envied obfuscation as secure secret storage.
- Run build_runner after any Envied change.

## Flutter Flavorizr

> **One-step wrapper.** `scripts/flavorize.sh [project_root]` runs
> `flutter_flavorizr -f` and handles gotchas #1 and #3 automatically (creates the
> per-flavor iOS `AppIcon-<flavor>` sets, asserts `flavorizr.gradle.kts` exists
> and is referenced). Author `flavorizr.yaml` first (org/app-name/bundleIds are
> project-specific), then run it. The manual gotcha notes below explain what it
> does and how to fix things by hand.

- Use `flutter_flavorizr` only when creating new projects or when the user
  explicitly asks in existing projects.
- It works best on clean projects.
- Create `flavorizr.yaml` at the project root.
- **Always run with `-f`.** Without it, flavorizr prompts interactively
  ("Do you want to proceed?") and a non-interactive/agent shell crashes with
  `Bad state: No terminal attached to stdout`:

  ```bash
  dart run flutter_flavorizr -f
  ```

### Three flavorizr gotchas that break the first build

1. **`AppIcon-<flavor>` missing → iOS build fails.** If you restrict
   `instructions:` to the native + `flutter:flavors` processors (to avoid
   overwriting your Dart entrypoints/app composition root), the iOS xcconfigs
   still set `ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-$(ASSET_PREFIX)"`,
   but the per-flavor icon sets are never created — Xcode then errors with
   *"None of the input catalogs contained a matching ... icon set named
   AppIcon-dev"*. Either include the icon processors, or create the sets by
   copying the default:

   ```bash
   cd ios/Runner/Assets.xcassets
   for f in dev staging prod; do cp -R AppIcon.appiconset "AppIcon-$f.appiconset"; done
   ```

2. **It overwrites Dart files.** The `flutter:app` / `flutter:pages` /
   `flutter:main` / `flutter:targets` processors regenerate `app/`, pages, and
   `main_*.dart` from flavorizr's own templates. To keep this skill's
   composition root and hand-written entrypoints, restrict `instructions:` to the
   native + `flutter:flavors` processors only, e.g.:

   ```yaml
   instructions:
     - android:androidManifest
     - android:flavorizrGradle  # WRITES android/app/flavorizr.gradle.kts (see gotcha #3)
     - android:buildGradle      # only injects `apply(from = "flavorizr.gradle.kts")`
     - ios:xcconfig
     - ios:buildTargets
     - ios:schema
     - ios:plist
     - flutter:flavors   # generates lib/flavors.dart (Flavor enum + F helper)
   ```

   Then hand-write `lib/main_<flavor>.dart` (set `Env` + `F.appFlavor`, call
   `runApplication()`), and apply gotcha #1 for the icons.

3. **Android: `android:buildGradle` alone leaves a dangling reference → Gradle
   fails.** Flavorizr splits the Android Gradle work across **two** instructions:
   `android:flavorizrGradle` *writes* `android/app/flavorizr.gradle.kts` (the
   `flavorDimensions` + `productFlavors`), while `android:buildGradle` only
   *injects* `apply(from = "flavorizr.gradle.kts")` into `build.gradle.kts`. List
   `android:buildGradle` without `android:flavorizrGradle` (as the example above
   now does — both are included) and you get a `build.gradle.kts` referencing a
   file that was never created; the Android build then fails with an unresolved
   `flavorizr.gradle.kts`. **`flutter analyze` and unit tests do NOT catch this**
   — only a real native build (or the gradle-file check in
   `scripts/validate_flutter_project.sh`) does. If you ever must run only
   `android:buildGradle`, author `flavorizr.gradle.kts` by hand:

   ```kotlin
   // android/app/flavorizr.gradle.kts
   import com.android.build.gradle.AppExtension

   val android = project.extensions.getByType(AppExtension::class.java)
   android.apply {
       flavorDimensions("flavor-type")
       productFlavors {
           create("dev") {
               dimension = "flavor-type"
               applicationId = "com.example.app.dev"
               resValue(type = "string", name = "app_name", value = "App Dev")
           }
           create("staging") {
               dimension = "flavor-type"
               applicationId = "com.example.app.staging"
               resValue(type = "string", name = "app_name", value = "App Staging")
           }
           create("prod") {
               dimension = "flavor-type"
               applicationId = "com.example.app"
               resValue(type = "string", name = "app_name", value = "App")
           }
       }
   }
   ```

Example `flavorizr.yaml` structure:

```yaml
flavors:
  dev:
    app:
      name: "App Dev"
    android:
      applicationId: "com.example.app.dev"
    ios:
      bundleId: "com.example.app.dev"
  staging:
    app:
      name: "App Staging"
    android:
      applicationId: "com.example.app.staging"
    ios:
      bundleId: "com.example.app.staging"
  prod:
    app:
      name: "App"
    android:
      applicationId: "com.example.app"
    ios:
      bundleId: "com.example.app"
```

When the app name/applicationId/bundleId are unknown, ask the user.
