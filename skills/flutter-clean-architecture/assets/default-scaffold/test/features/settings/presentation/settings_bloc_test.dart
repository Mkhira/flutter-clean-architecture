import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:__PKG__/features/settings/presentation/bloc/settings_bloc.dart';

class _MockStorage extends Mock implements Storage {}

void main() {
  late Storage storage;

  setUp(() {
    storage = _MockStorage();
    when(() => storage.write(any(), any<dynamic>())).thenAnswer((_) async {});
    when(() => storage.read(any())).thenReturn(null);
    HydratedBloc.storage = storage;
  });

  test('persists a locale change', () async {
    final bloc = SettingsBloc()..add(const SettingsLocaleChanged(Locale('ar')));
    await bloc.stream.first;

    expect(bloc.state.locale, const Locale('ar'));
    expect(
      SettingsState.fromJson(bloc.toJson(bloc.state)!).locale,
      const Locale('ar'),
    );
  });

  test('persists a theme mode change', () async {
    final bloc = SettingsBloc()
      ..add(const SettingsThemeModeChanged(ThemeMode.dark));
    await bloc.stream.first;

    expect(bloc.state.themeMode, ThemeMode.dark);
    expect(
      SettingsState.fromJson(bloc.toJson(bloc.state)!).themeMode,
      ThemeMode.dark,
    );
  });
}
