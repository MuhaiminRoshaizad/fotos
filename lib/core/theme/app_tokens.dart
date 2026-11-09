import 'package:flutter/animation.dart';

/// Spacing on a 4pt scale. Widgets use these, never ad-hoc numbers.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 28;
  static const double pill = 999;
}

/// Material icon sizes used across the app.
abstract final class AppIconSize {
  static const double badge = 16;
  static const double dense = 20;
  static const double standard = 24;
}

/// One rhythm for every animation in the app (Material 3 motion tokens).
abstract final class AppMotion {
  static const Duration short = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 400);

  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve decelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve accelerate = Cubic(0.3, 0, 0.8, 0.15);
}

/// Geometry of the floating navigation bar, shared by everything that must
/// clear it (lists, toasts, the selection bar).
abstract final class AppNavMetrics {
  static const double height = 68;
  static const double bottomGap = 16;

  /// Space a scrolling page leaves under its last row so the row ends above
  /// the floating bar and the system navigation bar.
  static double clearance(double systemBottomInset) =>
      height + bottomGap + systemBottomInset + AppSpacing.lg;
}
