import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

/// Diagnostics only — never business logic, never logs secrets/tokens.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    if (kDebugMode) {
      debugPrint('${bloc.runtimeType} $change');
    }
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('${bloc.runtimeType} error: $error');
    }
    super.onError(bloc, error, stackTrace);
  }
}
