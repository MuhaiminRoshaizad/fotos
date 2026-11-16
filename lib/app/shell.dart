import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/haptics/app_haptics.dart';
import '../core/selection/selection.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/bottom_bar_space.dart';
import '../features/video_editor/presentation/save_job.dart';
import 'edit_tabs_sheet.dart';
import 'floating_nav.dart';
import 'save_pill.dart';
import 'tab_order.dart';
import 'tab_root.dart';

/// Hosts the four tabs and the floating bar. The tabs show only on the four
/// main pages; a pushed page (an album, a folder) has the screen to itself.
/// While something is selected the selection bar takes the tabs' place, on
/// any page.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell, required this.location});

  final StatefulNavigationShell shell;

  /// The current address, to tell a main page from a pushed one.
  final String location;

  static const Set<String> _tabs = <String>{
    '/photos',
    '/videos',
    '/albums',
    '/files',
  };

  void _select(WidgetRef ref, int i) {
    ref.read(selectionProvider.notifier).clear();
    // A tab change ends a "press back again" that was waiting.
    ref.read(backToCloseProvider).disarm();
    // Tapping the current tab returns it to its first screen.
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SelectionState sel = ref.watch(selectionProvider);
    final bool onTab = _tabs.contains(location);
    final bool savingHidden = ref.watch(
      saveJobProvider.select((SaveJob? j) => j?.hidden ?? false),
    );
    final double bottom =
        MediaQuery.paddingOf(context).bottom + AppNavMetrics.bottomGap;
    return Scaffold(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // A save left to run in the background floats above the
                // tabs; selecting takes the space for the selection bar.
                AnimatedSwitcher(
                  duration: AppMotion.medium,
                  switchInCurve: AppMotion.decelerate,
                  switchOutCurve: AppMotion.accelerate,
                  transitionBuilder: _rise,
                  child: onTab && !sel.active && savingHidden
                      ? const Padding(
                          key: ValueKey<String>('save'),
                          padding: EdgeInsets.only(bottom: AppSpacing.md),
                          child: SavePill(),
                        )
                      : const SizedBox.shrink(key: ValueKey<String>('none')),
                ),
                AnimatedSwitcher(
                  duration: AppMotion.medium,
                  switchInCurve: AppMotion.decelerate,
                  switchOutCurve: AppMotion.accelerate,
                  transitionBuilder: _rise,
                  child: sel.active
                      ? SelectionBar(
                          key: const ValueKey<String>('selection'),
                          actions: <SelectionAction>[
                            for (final SelectionAction a in sel.actions)
                              if (a.isShownFor(sel.ids)) a,
                          ],
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bars come and go by fading as they rise from just below.
  static Widget _rise(Widget child, Animation<double> a) => FadeTransition(
    opacity: a,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.6),
        end: Offset.zero,
      ).animate(a),
      child: child,
    ),
  );
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
