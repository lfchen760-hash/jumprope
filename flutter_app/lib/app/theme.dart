import 'package:flutter/material.dart';

/// 设计稿色板（`design/ui-design-spec.md` §3.1）。
class AppColors {
  AppColors._();

  static const ink = Color(0xFF1C335F);
  static const inkSoft = Color(0xFF3C4E6C);
  static const muted = Color(0xFF7E786A);
  static const cream = Color(0xFFF9F8F3);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFEAE4D6);
  static const track = Color(0xFFF0EADD);

  static const brandOrange = Color(0xFFFF8A1F);
  static const brandPink = Color(0xFFFF2D6B);
  static const actionOrange = Color(0xFFF26A0A);
  static const actionPink = Color(0xFFE11D5A);

  static const success = Color(0xFF1EAA69);
  static const warn = Color(0xFFE89634);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandOrange, brandPink],
  );

  static const actionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [actionOrange, actionPink],
  );
}

TextStyle inkTitle(double size) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: AppColors.ink,
  height: 1.2,
);

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.brandOrange)
        .copyWith(primary: AppColors.ink, surface: AppColors.surface),
    scaffoldBackgroundColor: AppColors.cream,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: true,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}
