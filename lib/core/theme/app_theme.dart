import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoPageTransitionsBuilder, CupertinoThemeData;
import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Builds the light or dark theme. Neutrals follow iOS's system greys (white
/// and grouped grey in light; a soft near-black rather than pure black in
/// dark, which the owner finds harsh), with the cyanotype blue as the one
/// accent, brightened to iOS tint strength.
ThemeData buildAppTheme(Brightness brightness) {
  final bool light = brightness == Brightness.light;
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF2463EB),
        brightness: brightness,
      ).copyWith(
        primary: light ? const Color(0xFF2463EB) : const Color(0xFF5B9BFF),
        onPrimary: light ? const Color(0xFFFFFFFF) : const Color(0xFF001A40),
        primaryContainer: light
            ? const Color(0xFFE3ECFD)
            : const Color(0xFF16294A),
        onPrimaryContainer: light
            ? const Color(0xFF0B2A6B)
            : const Color(0xFFD6E3FA),
        surface: light ? const Color(0xFFFFFFFF) : const Color(0xFF111113),
        onSurface: light ? const Color(0xFF111114) : const Color(0xFFF2F2F5),
        onSurfaceVariant: light
            ? const Color(0xFF6C6C72)
            : const Color(0xFF9A9AA2),
        surfaceContainerLowest: light
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF0A0A0C),
        surfaceContainerLow: light
            ? const Color(0xFFF2F2F7)
            : const Color(0xFF1C1C1E),
        surfaceContainer: light
            ? const Color(0xFFEDEDF2)
            : const Color(0xFF222225),
        surfaceContainerHigh: light
            ? const Color(0xFFE5E5EA)
            : const Color(0xFF2C2C2E),
        surfaceContainerHighest: light
            ? const Color(0xFFD1D1D6)
            : const Color(0xFF3A3A3C),
        outlineVariant: light
            ? const Color(0xFFC6C6C8)
            : const Color(0xFF38383A),
        error: light ? const Color(0xFFD92D20) : const Color(0xFFFF453A),
        onError: const Color(0xFFFFFFFF),
        errorContainer: light
            ? const Color(0xFFFDE4E2)
            : const Color(0xFF3A1513),
      );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Inter',
    // Cupertino widgets (sheets, alerts, menus, nav bars) take the same accent
    // and translucent bar colour.
    cupertinoOverrideTheme: CupertinoThemeData(
      primaryColor: scheme.primary,
      barBackgroundColor: scheme.surface.withValues(alpha: 0.78),
      scaffoldBackgroundColor: scheme.surface,
    ),
    // iOS dims what you press; it never ripples.
    splashFactory: NoSplash.splashFactory,
    highlightColor: scheme.onSurface.withValues(alpha: 0.08),
    // App bars draw iOS's back chevron, not Android's arrow.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (BuildContext context) =>
          const Icon(CupertinoIcons.chevron_back),
    ),
    // Pages slide in from the right with the old page drifting behind.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
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
    // Task sheets look like iOS cards: grouped grey, 14 pt corners, grabber.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleSize: const Size(36, 5),
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    // Toasts float as a soft rounded banner rather than Material's snackbar.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: scheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: scheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

/// Rubber-band scrolling everywhere, as on iOS, with no Android stretch or
/// glow at the ends.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
