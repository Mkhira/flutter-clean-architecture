import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:__PKG__/features/settings/presentation/bloc/settings_bloc.dart';

class ThemeModeToggleButton extends StatelessWidget {
  const ThemeModeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final current = context.select<SettingsBloc, ThemeMode>(
      (b) => b.state.themeMode,
    );

    return PopupMenuButton<ThemeMode>(
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
  }
}
