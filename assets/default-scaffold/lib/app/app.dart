import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:__PKG__/app/app_bloc_observer.dart';
import 'package:__PKG__/core/di/injection.dart';
import 'package:__PKG__/core/router/app_router.dart';
import 'package:__PKG__/core/theme/app_theme.dart';
import 'package:__PKG__/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:path_provider/path_provider.dart';

/// Single shared startup path for every flavor entrypoint. Each
/// `main_<flavor>.dart` sets `Env` then calls this.
Future<void> runApplication() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory(
            (await getApplicationDocumentsDirectory()).path,
          ),
  );

  Bloc.observer = const AppBlocObserver();

  await configureDependencies();

  // HydratedBloc restores synchronously in its constructor, so the persisted
  // locale is available before building the app.
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
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (p, c) => p.locale != c.locale,
      listener: (context, state) => unawaited(context.setLocale(state.locale)),
      child: BlocBuilder<SettingsBloc, SettingsState>(
        buildWhen: (p, c) => p.themeMode != c.themeMode,
        builder: (context, settings) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          routerConfig: appRouter,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
        ),
      ),
    );
  }
}
