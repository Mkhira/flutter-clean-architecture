# Assets, flutter_gen & SVG

Goal: type-safe asset access (no stringly-typed paths that fail silently at
runtime), correct SVG rendering, and proper resolution/font declaration.

## Declare assets in pubspec

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/icons/
    - assets/lang/        # localization JSON (see localization.md)
```

List **directories** (trailing slash) rather than every file. Re-run `flutter pub
get` after editing the assets list.

## Resolution-aware images

Provide @2x / @3x variants beside the 1x file; Flutter picks per device DPR:

```text
assets/images/logo.png
assets/images/2.0x/logo.png
assets/images/3.0x/logo.png
```

Declaring `assets/images/` covers all three. Use `Image.asset`/`Assets...image()`
with the 1x path; Flutter resolves the variant.

## flutter_gen — type-safe asset accessors

Stop writing `'assets/images/logo.png'` (a typo fails only at runtime). Generate
accessors instead.

```yaml
dev_dependencies:
  build_runner: latest-compatible
  flutter_gen_runner: latest-compatible
```

Optional config (pubspec, top level) — enable the flutter_svg integration so SVGs
get an `.svg()` accessor:

```yaml
flutter_gen:
  integrations:
    flutter_svg: true
```

Generate (it reads the `flutter:` assets list; re-run after adding assets):

```bash
dart run build_runner build --delete-conflicting-outputs
```

Usage (default output is `lib/gen/assets.gen.dart`):

```dart
import 'package:<pkg>/gen/assets.gen.dart';

Assets.images.logo.image(width: 120);   // raster
Assets.icons.menu.svg(width: 24);        // SVG (needs the flutter_svg integration)
final String path = Assets.images.logo.path;
```

- `assets.gen.dart` is generated — never edit it; do not commit it ignored
  (commit it like other generated code, or gitignore consistently with `.g.dart`).
- Run the generator after changing the assets list — same trigger rule as other
  codegen (see `models-and-codegen.md` / `codegen-troubleshooting.md`).

## SVG — flutter_svg + the silent-failure gotcha

```yaml
dependencies:
  flutter_svg: latest-compatible
```

```dart
SvgPicture.asset(
  Assets.icons.logo.path, // or 'assets/icons/logo.svg'
  width: 24,
  // colorFilter recolors a single-color icon:
  colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
);
```

> **The gotcha that bites people:** flutter_svg does **not** support the full SVG
> spec. SVGs using **filters, masks, certain gradients, CSS styles, or `<use>`/
> blend modes** render **blank, clipped, or wrong** — with no error. When an SVG
> shows up empty:
> 1. Re-export from the design tool with filters/effects **flattened** (outline
>    strokes, expand masks, convert text to paths).
> 2. Or precompile with **`vector_graphics`** (`vector_graphics_compiler` →
>    `.vec`) and render with `VectorGraphic` — faster and stricter, surfaces
>    unsupported features at build time instead of silently.
> 3. For complex illustrations that won't flatten cleanly, fall back to a PNG.

## Fonts

Declare once in pubspec; consume via the theme (`TextTheme`), not per-widget
`fontFamily` (see `theme.md`):

```yaml
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```

```dart
ThemeData(fontFamily: 'Inter', /* ... */)
```

## Rules

- Prefer generated accessors (`Assets...`) over raw string paths.
- Declare asset directories, not individual files.
- Ship @2x/@3x for raster images that must stay crisp.
- For SVGs, assume flutter_svg is a *subset* renderer — flatten effects, or use
  `vector_graphics`; verify each SVG actually renders.
- Configure fonts once in pubspec + theme; never hardcode `fontFamily` per widget.
- Re-run build_runner after changing the assets list (flutter_gen).
