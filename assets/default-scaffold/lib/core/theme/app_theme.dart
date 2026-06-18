import 'package:flutter/material.dart';
import 'package:__PKG__/core/theme/app_colors.dart';
import 'package:__PKG__/core/theme/app_tokens.dart';

/// Single source of truth for light + dark [ThemeData].
abstract class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: const [AppTokens.fallback],
    );
  }
}
