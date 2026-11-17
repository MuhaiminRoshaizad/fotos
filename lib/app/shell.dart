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
    // A save left to run in the background shows on every page, the pushed
    // ones too; only selecting takes its place.
    final bool pill = savingHidden && !sel.active;
    final bool bar = sel.active || onTab;
    return Scaffold(
      // The keyboard covers the tab bar, as on iOS; without this the bar
      // rode up above the keyboard, over whatever dialog was asking.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: BottomBarSpace(shown: bar || pill, child: shell),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedSwitcher(
                  duration: AppMotion.medium,
                  switchInCurve: AppMotion.decelerate,
                  switchOutCurve: AppMotion.accelerate,
                  transitionBuilder: _rise,
                  child: pill
                      ? const SavePill(key: ValueKey<String>('save'))
                      : const SizedBox.shrink(key: ValueKey<String>('none')),
                ),
                // The bar's room opens and closes smoothly, so the pill
                // above glides down as the tabs leave for a pushed page and
                // back up as they return, instead of jumping once the bar
                // has finished going.
                // An even ease over 400 ms: the emphasized curve put a third
                // of the trip into one frame, which reads as a lurch.
                AnimatedSize(
                  duration: AppMotion.long,
                  curve: Curves.easeInOut,
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (pill && bar) const SizedBox(height: AppSpacing.md),
                      AnimatedSwitcher(
                        duration: AppMotion.medium,
                        switchInCurve: AppMotion.decelerate,
                        switchOutCurve: AppMotion.accelerate,
                        transitionBuilder: _rise,
                        layoutBuilder: _currentSized,
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
                            : const SizedBox.shrink(
                                key: ValueKey<String>('none'),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Lays a switch out at the size of the bar coming in alone: the one
  /// going out still shows, pinned to the bottom, but takes no room.
  /// The full width, so a bar going out keeps its own width whatever the
  /// one coming in measures.
  static Widget _currentSized(Widget? current, List<Widget> previous) =>
      SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: <Widget>[
            for (final Widget p in previous)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: p,
                ),
              ),
            ?current,
          ],
        ),
      );

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
