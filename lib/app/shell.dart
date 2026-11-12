import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/haptics/app_haptics.dart';
import '../core/selection/selection.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/bottom_bar_space.dart';
import '../core/widgets/toast.dart';
import 'edit_tabs_sheet.dart';
import 'floating_nav.dart';
import 'tab_order.dart';

/// Hosts the four tabs and the floating bar. The tabs show only on the four
/// main pages; a pushed page (an album, a folder) has the screen to itself.
/// While something is selected the selection bar takes the tabs' place, on
/// any page.
///
/// Back on a main page follows Android's rule for bottom tabs: another tab
/// goes back to the first one, and only the first one leaves the app, after
/// a "press back again" toast so a stray swipe doesn't close fotos.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell, required this.location});

  final StatefulNavigationShell shell;

  /// The current address, to tell a main page from a pushed one.
  final String location;

  /// How long a second Back still closes the app: as long as the toast
  /// asking for it shows.
  static const Duration closeWindow = Duration(seconds: 3);

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get shell => widget.shell;

  /// Runs while the "press back again" toast shows; a Back meanwhile
  /// closes the app.
  Timer? _asking;

  @override
  void dispose() {
    _asking?.cancel();
    super.dispose();
  }

  void _select(WidgetRef ref, int i) {
    ref.read(selectionProvider.notifier).clear();
    // Tapping the current tab returns it to its first screen.
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  void _back() {
    final int first = ref.read(tabOrderProvider).first;
    if (shell.currentIndex != first) {
      _asking?.cancel();
      _select(ref, first);
      return;
    }
    if (_asking?.isActive ?? false) {
      _asking!.cancel();
      SystemNavigator.pop();
      return;
    }
    _asking = Timer(AppShell.closeWindow, () {});
    showToast(context, 'Press back again to close fotos');
  }

  @override
  Widget build(BuildContext context) {
    final SelectionState sel = ref.watch(selectionProvider);
    final bool onTab = tabPaths.contains(widget.location);
    final double bottom =
        MediaQuery.paddingOf(context).bottom + AppNavMetrics.bottomGap;
    return PopScope(
      // Pages pushed on a tab, and a tab's own selection, go back first;
      // this only sees Back once nothing on the tab is left to close.
      canPop: !onTab,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        // The keyboard covers the tab bar, as on iOS; without this the bar
        // rode up above the keyboard, over whatever dialog was asking.
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: BottomBarSpace(shown: onTab || sel.active, child: shell),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom,
              child: Center(
                child: AnimatedSwitcher(
                  duration: AppMotion.medium,
                  switchInCurve: AppMotion.decelerate,
                  switchOutCurve: AppMotion.accelerate,
                  transitionBuilder: (Widget child, Animation<double> a) =>
                      FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.6),
                            end: Offset.zero,
                          ).animate(a),
                          child: child,
                        ),
                      ),
                  child: sel.active
                      ? SelectionBar(
                          key: const ValueKey<String>('selection'),
                          actions: sel.actions,
                          enabled: sel.ids.isNotEmpty,
                          onAction: (SelectionAction a) =>
                              a.run(context, sel.ids),
                        )
                      : onTab
                      ? FloatingNav(
                          key: const ValueKey<String>('nav'),
                          index: shell.currentIndex,
                          order: ref.watch(tabOrderProvider),
                          onSelect: (int i) => _select(ref, i),
                          onLongPress: () {
                            AppHaptics.longPress();
                            showEditTabs(context, ref);
                          },
                        )
                      : const SizedBox.shrink(key: ValueKey<String>('none')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Switches tabs instantly, as iOS does: a tab change happens dozens of
/// times a day, so it gets no animation. Inactive tabs stay mounted, with
/// their tickers paused, so each keeps its scroll position and stack.
class TabBranches extends StatelessWidget {
  const TabBranches({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        for (int i = 0; i < children.length; i++)
          Positioned.fill(
            child: Offstage(
              offstage: i != index,
              child: TickerMode(enabled: i == index, child: children[i]),
            ),
          ),
      ],
    );
  }
}
