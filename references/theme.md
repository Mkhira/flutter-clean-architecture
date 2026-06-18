# Theme / Design System

Goal: centralize colors, typography, spacing, radii, and component styling under
`core/theme/` so widgets consume tokens instead of hardcoded values.

## Suggested files

```text
core/theme/app_theme.dart            // light + dark ThemeData builders
core/theme/app_colors.dart           // raw color tokens / seed colors
core/theme/app_text_styles.dart      // text tokens (or build from TextTheme)
core/theme/app_spacing.dart          // spacing scale
core/theme/app_theme_extension.dart  // ThemeExtension for brand-specific tokens
```

## Rules

- Define a single source of truth under `core/theme/`.
- Provide both light and dark `ThemeData`.
- Drive colors from a `ColorScheme` (`ColorScheme.fromSeed` or explicit values),
  with `useMaterial3: true`.
- Define a `TextTheme` once; widgets read `Theme.of(context).textTheme`, not
  ad-hoc `TextStyle`.
- For custom tokens not covered by `ThemeData` (brand colors, spacing scale,
  radii), use a `ThemeExtension`.
- Configure fonts once (in `pubspec.yaml` + theme), not per widget.
- Use `flutter_screenutil_plus` for responsive sizing; do not bake
  device-specific pixel values into the theme.
- Honor RTL: prefer `EdgeInsetsDirectional` over `EdgeInsets.only(left/right)`.
- Theme/locale selection belongs in a small persisted settings Bloc/Cubit
  (HydratedBloc/HydratedCubit) so it survives restarts; never store secrets
  there. See the settings `SettingsBloc` (locale persistence) in
  `localization.md` — add `themeMode` to the same `SettingsState`.

## ThemeData wiring

```dart
ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.seed);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: const [
      AppTokens(brandPrimary: AppColors.seed, spacingMd: 16),
    ],
  );
}
```

## ThemeExtension for brand tokens

```dart
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({required this.brandPrimary, required this.spacingMd});

  final Color brandPrimary;
  final double spacingMd;

  @override
  AppTokens copyWith({Color? brandPrimary, double? spacingMd}) => AppTokens(
        brandPrimary: brandPrimary ?? this.brandPrimary,
        spacingMd: spacingMd ?? this.spacingMd,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t)!,
      spacingMd: lerpDouble(spacingMd, other.spacingMd, t)!,
    );
  }
}
```

Usage in a widget:

```dart
final tokens = Theme.of(context).extension<AppTokens>()!;
```

## Persisting & toggling theme mode

The selected light/dark/system mode lives in the same persisted `SettingsState`
as the locale (see `localization.md` for the model + `SettingsBloc`). Add a
`ThemeMode themeMode` field and a `SettingsThemeModeChanged` event, then drive
`MaterialApp.themeMode` from the Bloc — provide light + dark `ThemeData` and let
Flutter pick:

```dart
BlocBuilder<SettingsBloc, SettingsState>(
  buildWhen: (p, c) => p.themeMode != c.themeMode,
  builder: (context, settings) => MaterialApp.router(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: settings.themeMode, // system / light / dark
    routerConfig: appRouter,
    localizationsDelegates: context.localizationDelegates,
    supportedLocales: context.supportedLocales,
    locale: context.locale,
  ),
)
```

Theme toggle button (a `PopupMenuButton` over `ThemeMode.values`):

```dart
final current =
    context.select<SettingsBloc, ThemeMode>((b) => b.state.themeMode);

PopupMenuButton<ThemeMode>(
  icon: const Icon(Icons.brightness_6_outlined),
  tooltip: 'settings.theme'.tr(),
  onSelected: (mode) =>
      context.read<SettingsBloc>().add(SettingsThemeModeChanged(mode)),
  itemBuilder: (context) => [
    for (final mode in ThemeMode.values)
      CheckedPopupMenuItem<ThemeMode>(
        value: mode,
        checked: mode == current,
        child: Text('theme_mode.${mode.name}'.tr()),
      ),
  ],
);
```

Add `theme_mode.system|light|dark` and `settings.theme` keys to both translation
files. Unlike locale, theme mode does not go through easy_localization — it is
read straight from the Bloc into `MaterialApp.themeMode`.

## Anti-patterns

- Do not scatter `Color(0xFF...)` across widgets.
- Do not create one-off `TextStyle` where a theme token exists.
- Do not duplicate spacing constants per widget.
