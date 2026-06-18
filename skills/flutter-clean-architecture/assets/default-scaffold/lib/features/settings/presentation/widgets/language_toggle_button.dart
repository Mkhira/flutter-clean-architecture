import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:__PKG__/features/settings/presentation/bloc/settings_bloc.dart';

class LanguageToggleButton extends StatelessWidget {
  const LanguageToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.language),
      tooltip: 'settings.language'.tr(),
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
    );
  }
}
