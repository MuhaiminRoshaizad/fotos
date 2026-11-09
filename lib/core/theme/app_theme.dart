import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Builds the light or dark theme from one palette: a cyanotype blue accent
/// over neutrals biased slightly towards it.
ThemeData buildAppTheme(Brightness brightness) {
  final bool light = brightness == Brightness.light;
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF1D5BBF),
        brightness: brightness,
      ).copyWith(
        primary: light ? const Color(0xFF1D5BBF) : const Color(0xFF8FB5F7),
        onPrimary: light ? const Color(0xFFFFFFFF) : const Color(0xFF0B1A33),
        primaryContainer: light
            ? const Color(0xFFDCE7F8)
            : const Color(0xFF1F3352),
        onPrimaryContainer: light
            ? const Color(0xFF0B2A5C)
            : const Color(0xFFD6E3FA),
        surface: light ? const Color(0xFFFAFBFD) : const Color(0xFF0F1218),
        onSurface: light ? const Color(0xFF121821) : const Color(0xFFE7EBF1),
        onSurfaceVariant: light
            ? const Color(0xFF55606E)
            : const Color(0xFF9BA6B5),
        surfaceContainerLowest: light
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF0B0E13),
        surfaceContainerLow: light
            ? const Color(0xFFF3F6F9)
            : const Color(0xFF151920),
        surfaceContainer: light
            ? const Color(0xFFECF0F5)
            : const Color(0xFF1B2029),
        surfaceContainerHigh: light
            ? const Color(0xFFE5EAF0)
            : const Color(0xFF222833),
        surfaceContainerHighest: light
            ? const Color(0xFFDFE5EC)
            : const Color(0xFF2C3340),
        outlineVariant: light
            ? const Color(0xFFDCE2EA)
            : const Color(0xFF2A313C),
        error: light ? const Color(0xFFB3261E) : const Color(0xFFF2B8B5),
        onError: light ? const Color(0xFFFFFFFF) : const Color(0xFF601410),
        errorContainer: light
            ? const Color(0xFFF9DEDC)
            : const Color(0xFF4A1F1C),
      );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.onSurface,
      contentTextStyle: TextStyle(color: scheme.surface, fontSize: 14),
      actionTextColor: scheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide.none,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      minVerticalPadding: AppSpacing.sm,
    ),
  );
}
