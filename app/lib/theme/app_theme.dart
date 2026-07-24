import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Light and dark themes. Each registers its [AppColorsData] extension.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(AppColorsData.light, Brightness.light);
  static ThemeData get dark => _build(AppColorsData.dark, Brightness.dark);

  static ThemeData _build(AppColorsData c, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: c.onPrimaryContainer,
      secondary: c.secondary,
      onSecondary: c.onSecondary,
      secondaryContainer: c.secondaryContainer,
      onSecondaryContainer: c.onSecondaryContainer,
      tertiary: c.tertiary,
      onTertiary: c.onPrimary,
      error: c.error,
      onError: c.onError,
      errorContainer: c.errorContainer,
      onErrorContainer: c.onErrorContainer,
      surface: c.surface,
      onSurface: c.onSurface,
      onSurfaceVariant: c.onSurfaceVariant,
      outline: c.outline,
      outlineVariant: c.outlineVariant,
      surfaceContainerLowest: c.surfaceContainerLowest,
      surfaceContainerLow: c.surfaceContainerLow,
      surfaceContainer: c.surfaceContainer,
      surfaceContainerHigh: c.surfaceContainerHigh,
      surfaceContainerHighest: c.surfaceContainerHighest,
    );

    // Inter everywhere, with the theme's default text color.
    final textTheme = GoogleFonts.interTextTheme()
        .apply(bodyColor: c.onSurface, displayColor: c.onSurface)
        .copyWith(
          headlineLarge: AppText.headlineLg,
          headlineMedium: AppText.headlineMd,
          headlineSmall: AppText.headlineSm,
          bodyLarge: AppText.bodyLg,
          bodyMedium: AppText.bodyMd,
          bodySmall: AppText.bodySm,
          labelLarge: AppText.labelLg,
          labelMedium: AppText.labelMd,
        );

    OutlineInputBorder border(Color color, {double width = 1}) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.surface,
      extensions: [c],
      textTheme: textTheme,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: border(c.outline),
        enabledBorder: border(c.outline),
        focusedBorder: border(c.primary, width: 2),
        errorBorder: border(c.error),
        focusedErrorBorder: border(c.error, width: 2),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primaryContainer,
          foregroundColor: brightness == Brightness.dark ? c.onPrimaryContainer : c.onPrimary,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: AppText.labelLg,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.onSurface,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: c.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: AppText.labelLg,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary),
      ),
    );
  }
}

/// Named text styles (Inter) without color, so they adapt to the theme.
class AppText {
  AppText._();

  static TextStyle get headlineLg => GoogleFonts.inter(
      fontSize: 32, fontWeight: FontWeight.w700, height: 40 / 32, letterSpacing: -0.64);
  static TextStyle get headlineMd => GoogleFonts.inter(
      fontSize: 24, fontWeight: FontWeight.w600, height: 32 / 24, letterSpacing: -0.24);
  static TextStyle get headlineSm => GoogleFonts.inter(
      fontSize: 20, fontWeight: FontWeight.w600, height: 28 / 20);
  static TextStyle get bodyLg => GoogleFonts.inter(
      fontSize: 18, fontWeight: FontWeight.w400, height: 28 / 18);
  static TextStyle get bodyMd => GoogleFonts.inter(
      fontSize: 16, fontWeight: FontWeight.w400, height: 24 / 16);
  static TextStyle get bodySm => GoogleFonts.inter(
      fontSize: 14, fontWeight: FontWeight.w400, height: 20 / 14);
  static TextStyle get labelLg => GoogleFonts.inter(
      fontSize: 14, fontWeight: FontWeight.w600, height: 20 / 14, letterSpacing: 0.14);
  static TextStyle get labelMd => GoogleFonts.inter(
      fontSize: 12, fontWeight: FontWeight.w500, height: 16 / 12, letterSpacing: 0.24);
}
