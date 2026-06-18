import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:__PKG__/core/theme/app_colors.dart';

/// Brand-specific tokens not covered by [ThemeData] (brand color, spacing
/// scale). Read with `Theme.of(context).extension<AppTokens>()!`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({required this.brandPrimary, required this.spacingMd});

  static const AppTokens fallback = AppTokens(
    brandPrimary: AppColors.seed,
    spacingMd: 16,
  );

  final Color brandPrimary;
  final double spacingMd;

  @override
  AppTokens copyWith({Color? brandPrimary, double? spacingMd}) => AppTokens(
    brandPrimary: brandPrimary ?? this.brandPrimary,
    spacingMd: spacingMd ?? this.spacingMd,
  );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t)!,
      spacingMd: lerpDouble(spacingMd, other.spacingMd, t)!,
    );
  }
}
