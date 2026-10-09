import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Near-black surfaces with a viewfinder amber accent.
abstract final class SphereColors {
  static const background = Color(0xFF070708);
  static const surface = Color(0xFF141416);
  static const surfaceHigh = Color(0xFF2A2A30);
  static const accent = Color(0xFFF5C518);
  static const captured = Color(0xFF3DDC97);
  static const ink = Color(0xFF0B0B0D);
  static const muted = Color(0xFF9A9AA3);
  static const danger = Color(0xFFFF5C5C);
}

abstract final class SphereTheme {
  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: SphereColors.accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: SphereColors.accent,
          onPrimary: SphereColors.ink,
          secondary: SphereColors.captured,
          onSecondary: SphereColors.ink,
          surface: SphereColors.background,
          error: SphereColors.danger,
          onError: Colors.white,
        );

    final borderRadius = BorderRadius.circular(14);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: SphereColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: SphereColors.background,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SphereColors.surface,
        labelStyle: const TextStyle(color: SphereColors.muted),
        hintStyle: const TextStyle(color: SphereColors.muted),
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: SphereColors.surfaceHigh),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: SphereColors.accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: SphereColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: SphereColors.danger, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SphereColors.accent,
          foregroundColor: SphereColors.ink,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: SphereColors.accent),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SphereColors.surfaceHigh,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }
}
