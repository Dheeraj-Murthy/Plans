import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF151618);
  static const surface = Color(0xFF1B1D21);
  static const elevated = Color(0xFF23262B);

  static const border = Color(0xFF2D3138);

  static const textPrimary = Color(0xFFF3F4F6);
  static const textSecondary = Color(0xFFA1A8B3);
  static const textMuted = Color(0xFF6B7280);

  static const accent = Color(0xFF7C6DF2);
  static const accentHover = Color(0xFF9185FF);
  static const accentPressed = Color(0xFF6B5BEA);

  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);

  static const priorityCritical = Color(0xFFFF1744);
  static const priorityHigh = Color(0xFFE45C5C);
  static const priorityMedium = Color(0xFFE8943A);
  static const priorityLow = Color(0xFF5E8AE4);

  static const projectColors = [
    Color(0xFF7C6DF2),
    Color(0xFFE45C5C),
    Color(0xFF3CAE7C),
    Color(0xFFE8943A),
    Color(0xFF5E8AE4),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.dark(
          primary: AppColors.accent,
          onPrimary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          error: AppColors.danger,
          outline: AppColors.border,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppColors.elevated,
          contentTextStyle: TextStyle(color: AppColors.textPrimary),
          actionTextColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: AppColors.border),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.border,
          thickness: 1,
          space: 0,
        ),

      );
}
