# Responsive UI

## Packages

```yaml
flutter_screenutil_plus: latest-compatible
cached_network_image: latest-compatible
```

## Rules

- Initialize `ScreenUtilPlusInit` at the app root.
- Use theme tokens and app text styles before ad hoc styles (see `theme.md`).
- Use responsive sizing consistently.
- Prefer context-aware extensions when appropriate.
- Do not overuse responsive scaling where native Flutter layout is better.
- Use `CachedNetworkImage` for remote images with placeholder and errorWidget.
- Do not let image loading failures break the UI.

## CachedNetworkImage example

```dart
CachedNetworkImage(
  imageUrl: imageUrl,
  placeholder: (context, url) => const CircularProgressIndicator(),
  errorWidget: (context, url, error) => const Icon(Icons.error),
)
```

## ScreenUtilPlus root pattern

The class name `ScreenUtilPlusInit` is correct for `flutter_screenutil_plus`.

```dart
ScreenUtilPlusInit(
  designSize: const Size(390, 844),
  minTextAdapt: true,
  splitScreenMode: true,
  builder: (context, child) {
    return MaterialApp.router(
      routerConfig: router,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  },
)
```

Adapt to the package API and project conventions.
