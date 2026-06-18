import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'settings_event.dart';
part 'settings_state.dart';

/// Persists the selected locale and theme mode across restarts. HydratedBloc
/// is the single source of truth (easy_localization persistence is turned off).
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
