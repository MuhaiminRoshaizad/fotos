import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';

/// Whether the shell's floating bar (the tabs, or the selection bar) is on
/// screen. The tabs show only on the four main pages, so a pushed page such
/// as an album or a folder has the bottom of the screen to itself.
class BottomBarSpace extends InheritedWidget {
  const BottomBarSpace({super.key, required this.shown, required super.child});

  final bool shown;

  static bool shownOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BottomBarSpace>()?.shown ??
      false;

  @override
  bool updateShouldNotify(BottomBarSpace old) => old.shown != shown;
}

/// Space a scrolling page leaves under its last row: enough to end above
/// the floating bar when it shows, and above the system navigation bar
/// always.
double bottomClearance(BuildContext context) {
  final double inset = MediaQuery.paddingOf(context).bottom;
  return BottomBarSpace.shownOf(context)
      ? AppNavMetrics.clearance(inset)
      : inset + AppSpacing.lg;
}
