import 'package:flutter/material.dart';

/// App color palette with light and dark variants, registered as a
/// [ThemeExtension] and read with `context.colors.X`.
@immutable
class AppColorsData extends ThemeExtension<AppColorsData> {
  // Surfaces
  final Color surface;
  final Color surfaceDim;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color surfaceVariant;
  // Text on surfaces
  final Color onSurface;
  final Color onSurfaceVariant;
  // Primary
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color primaryFixed;
  final Color primaryFixedDim;
  // Secondary
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  // Tertiary / warnings
  final Color tertiary;
  final Color tertiaryContainer;
  final Color warning;
  // Error
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  // Outlines
  final Color outline;
  final Color outlineVariant;

  const AppColorsData({
    required this.surface,
    required this.surfaceDim,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.surfaceVariant,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.primaryFixed,
    required this.primaryFixedDim,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.tertiaryContainer,
    required this.warning,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.outline,
    required this.outlineVariant,
  });

  static const light = AppColorsData(
    surface: Color(0xFFFAF8FF),
    surfaceDim: Color(0xFFDAD9E4),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF3F2FD),
    surfaceContainer: Color(0xFFEEEDF8),
    surfaceContainerHigh: Color(0xFFE8E7F2),
    surfaceContainerHighest: Color(0xFFE2E1EC),
    surfaceVariant: Color(0xFFE2E1EC),
    onSurface: Color(0xFF1A1B23),
    onSurfaceVariant: Color(0xFF474553),
    primary: Color(0xFF3B309E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF534AB7),
    onPrimaryContainer: Color(0xFFD1CCFF),
    primaryFixed: Color(0xFFE3DFFF),
    primaryFixedDim: Color(0xFFC5C0FF),
    secondary: Color(0xFF006C4E),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF83F5C6),
    onSecondaryContainer: Color(0xFF007151),
    tertiary: Color(0xFF7D2200),
    tertiaryContainer: Color(0xFFA2340A),
    warning: Color(0xFFBA7517),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    outline: Color(0xFF787584),
    outlineVariant: Color(0xFFC8C4D5),
  );

  static const dark = AppColorsData(
    surface: Color(0xFF131318),
    surfaceDim: Color(0xFF131318),
    surfaceContainerLowest: Color(0xFF0D0E13),
    surfaceContainerLow: Color(0xFF1B1B21),
    surfaceContainer: Color(0xFF1F1F25),
    surfaceContainerHigh: Color(0xFF2A2930),
    surfaceContainerHighest: Color(0xFF35343B),
    surfaceVariant: Color(0xFF47464F),
    onSurface: Color(0xFFE5E1E9),
    onSurfaceVariant: Color(0xFFC9C5D0),
    primary: Color(0xFFC5C0FF),
    onPrimary: Color(0xFF29157A),
    primaryContainer: Color(0xFF4A419F),
    onPrimaryContainer: Color(0xFFE3DFFF),
    primaryFixed: Color(0xFFE3DFFF),
    primaryFixedDim: Color(0xFFC5C0FF),
    secondary: Color(0xFF68DBAE),
    onSecondary: Color(0xFF003826),
    secondaryContainer: Color(0xFF00513A),
    onSecondaryContainer: Color(0xFF86F8C9),
    tertiary: Color(0xFFFFB59E),
    tertiaryContainer: Color(0xFF852400),
    warning: Color(0xFFE7B15A),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    outline: Color(0xFF928F9A),
    outlineVariant: Color(0xFF47464F),
  );

  @override
  AppColorsData copyWith({
    Color? surface,
    Color? surfaceDim,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? surfaceVariant,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? tertiary,
    Color? tertiaryContainer,
    Color? warning,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? outline,
    Color? outlineVariant,
  }) {
    return AppColorsData(
      surface: surface ?? this.surface,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      surfaceContainerLowest: surfaceContainerLowest ?? this.surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest ?? this.surfaceContainerHighest,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      primaryFixed: primaryFixed ?? this.primaryFixed,
      primaryFixedDim: primaryFixedDim ?? this.primaryFixedDim,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      onSecondaryContainer: onSecondaryContainer ?? this.onSecondaryContainer,
      tertiary: tertiary ?? this.tertiary,
      tertiaryContainer: tertiaryContainer ?? this.tertiaryContainer,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
    );
  }

  @override
  AppColorsData lerp(ThemeExtension<AppColorsData>? other, double t) {
    // The extra colors switch at the midpoint; ColorScheme already animates.
    if (other is! AppColorsData) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppColorsX on BuildContext {
  AppColorsData get colors => Theme.of(this).extension<AppColorsData>()!;
}
