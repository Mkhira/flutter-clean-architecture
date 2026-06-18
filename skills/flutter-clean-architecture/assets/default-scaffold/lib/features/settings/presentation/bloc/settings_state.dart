part of 'settings_bloc.dart';

/// One serializable model holds every persisted setting. Non-JSON types are
/// stored as primitives (`Locale` -> languageCode, `ThemeMode` -> enum name).
final class SettingsState extends Equatable {
  const SettingsState({
    this.locale = const Locale('en'),
    this.themeMode = ThemeMode.system,
  });

  factory SettingsState.fromJson(Map<String, dynamic> json) => SettingsState(
    locale: Locale(json['languageCode'] as String? ?? 'en'),
    themeMode:
        ThemeMode.values.asNameMap()[json['themeMode']] ?? ThemeMode.system,
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
