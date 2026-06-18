# Localization

Use `easy_localization` together with the SDK delegates.

## SDK dependency (required for built-in widget localization + RTL)

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  easy_localization: latest-compatible
```

easy_localization re-exports the global Material/Cupertino/Widgets delegates
through `context.localizationDelegates`, but `flutter_localizations` must be
present so that built-in widgets (date pickers, default labels) and RTL behave
correctly.

## Required project-root assets

```text
assets/
└── lang/
    ├── en.json
    └── ar.json
```

> **Locale codes:** use language-only locales `Locale('en')` and `Locale('ar')`
> with files `en.json` / `ar.json`. If region-specific locales are needed, use
> **valid ISO 3166 region codes** (e.g. `Locale('en', 'US')` → `en-US.json`,
> `Locale('ar', 'SA')` → `ar-SA.json`). Do NOT use invented region codes like
> `EN` (not a country) or `AR` (that is Argentina, not an Arabic region). File
> names must exactly match the `supportedLocales` entries.

`assets/` is at project root scope, not inside `lib`.

Add to `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/lang/
```

iOS: declare supported locales in `ios/Runner/Info.plist`:

```xml
<key>CFBundleLocalizations</key>
<array>
  <string>en</string>
  <string>ar</string>
</array>
```

## Initial JSON files

`assets/lang/en.json`:

```json
{
  "app": {
    "name": "App"
  },
  "common": {
    "ok": "OK",
    "cancel": "Cancel",
    "retry": "Retry",
    "loading": "Loading...",
    "network_error": "Please check your internet connection.",
    "server_error": "Something went wrong on the server.",
    "unknown_error": "Something went wrong."
  },
  "counter": {
    "title": "Counter"
  }
}
```

`assets/lang/ar.json`:

```json
{
  "app": {
    "name": "التطبيق"
  },
  "common": {
    "ok": "موافق",
    "cancel": "إلغاء",
    "retry": "إعادة المحاولة",
    "loading": "جاري التحميل...",
    "network_error": "يرجى التحقق من اتصال الإنترنت.",
    "server_error": "حدث خطأ في الخادم.",
    "unknown_error": "حدث خطأ ما."
  },
  "counter": {
    "title": "العداد"
  }
}
```

## Initialization

```dart
await EasyLocalization.ensureInitialized();

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
```

`MaterialApp` or `MaterialApp.router`:

```dart
localizationsDelegates: context.localizationDelegates,
supportedLocales: context.supportedLocales,
locale: context.locale,
```

## Persisting the selected locale (settings HydratedBloc)

For a change-language button whose choice survives restarts, persist the locale
in a small **settings HydratedBloc** (`features/settings/presentation/bloc/`) and
make it the single source of truth. easy_localization can persist locale itself,
so turn that off (`saveLocale: false`) to avoid two competing stores, and seed
its `startLocale` from the persisted state.

Serializable settings model — one model holds every persisted setting (locale,
theme mode, ...). Non-JSON types are stored as primitives (`Locale` →
`languageCode`, `ThemeMode` → enum name):

```dart
final class SettingsState extends Equatable {
  const SettingsState({
    this.locale = const Locale('en'),
    this.themeMode = ThemeMode.system,
  });

  factory SettingsState.fromJson(Map<String, dynamic> json) => SettingsState(
        locale: Locale(json['languageCode'] as String? ?? 'en'),
        themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ??
            ThemeMode.system,
      );

  final Locale locale;
  final ThemeMode themeMode;

  SettingsState copyWith({Locale? locale, ThemeMode? themeMode}) =>
      SettingsState(
        locale: locale ?? this.locale,
        themeMode: themeMode ?? this.themeMode,
      );

  Map<String, dynamic> toJson() => {
        'languageCode': locale.languageCode,
        'themeMode': themeMode.name,
      };

  @override
  List<Object?> get props => [locale, themeMode];
}

final class SettingsBloc extends HydratedBloc<SettingsEvent, SettingsState> {
  SettingsBloc() : super(const SettingsState()) {
    on<SettingsLocaleChanged>(
      (event, emit) => emit(state.copyWith(locale: event.locale)),
    );
    on<SettingsThemeModeChanged>(
      (event, emit) => emit(state.copyWith(themeMode: event.themeMode)),
    );
  }

  @override
  SettingsState? fromJson(Map<String, dynamic> json) =>
      SettingsState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(SettingsState state) => state.toJson();
}
```

`themeMode` is driven into `MaterialApp.themeMode` and toggled with the same
pattern as the language button — see `theme.md`.

Startup — HydratedBloc restores synchronously in its constructor, so read the
persisted locale before building the app (register `SettingsBloc` as a DI lazy
**singleton**: it is long-lived app state):

```dart
final settingsBloc = getIt<SettingsBloc>();
runApp(
  EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('ar')],
    path: 'assets/lang',
    fallbackLocale: const Locale('en'),
    startLocale: settingsBloc.state.locale,
    saveLocale: false, // HydratedBloc is the source of truth
    child: BlocProvider.value(value: settingsBloc, child: const App()),
  ),
);
```

Apply later changes with a `BlocListener` at the app root (so the button only
dispatches an event — no duplicated `setLocale` calls). `context.setLocale`
returns a `Future`; wrap it in `unawaited` (from `dart:async`) so the listener
does not trip `discarded_futures` under `very_good_analysis`:

```dart
import 'dart:async';

BlocListener<SettingsBloc, SettingsState>(
  listenWhen: (p, c) => p.locale != c.locale,
  listener: (context, state) => unawaited(context.setLocale(state.locale)),
  child: /* MaterialApp.router ... */,
)
```

Change-language button (a `PopupMenuButton` over `context.supportedLocales`):

```dart
PopupMenuButton<Locale>(
  icon: const Icon(Icons.language),
  onSelected: (locale) =>
      context.read<SettingsBloc>().add(SettingsLocaleChanged(locale)),
  itemBuilder: (context) => [
    for (final locale in context.supportedLocales)
      CheckedPopupMenuItem<Locale>(
        value: locale,
        checked: locale == context.locale,
        child: Text('language.${locale.languageCode}'.tr()),
      ),
  ],
)
```

Add native language names to both files (same in each, so each is recognizable
regardless of the active language):

```json
"language": { "en": "English", "ar": "العربية" }
```

Switching to Arabic flips the app to RTL automatically (the SDK delegates handle
directionality) — which is exactly why `flutter_localizations` and
`EdgeInsetsDirectional` matter.

## Rules

- Do not hardcode user-facing strings in widgets after localization is
  configured.
- Use `.tr()` or generated keys if the project uses them.
- Keep translation keys stable and grouped.
- Add keys to both `en.json` and `ar.json`.
- For RTL Arabic, ensure UI does not force LTR unless needed; prefer
  `EdgeInsetsDirectional` and directional alignment.
- If using code generation for localization keys, run the easy_localization
  generator separately.
- Optional audit (find keys used in code but missing from translations):

  ```bash
  dart run easy_localization:audit --translations-dir assets/lang --source-dir lib
  ```

  > Verify the exact subcommand/flags for the installed easy_localization
  > version; the audit feature exists, but flag names can differ between
  > versions. Default translations path is `assets/translations`, so the custom
  > `--translations-dir` is required here.
