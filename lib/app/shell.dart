import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/selection/selection.dart';
import '../core/theme/app_tokens.dart';
import 'floating_nav.dart';

/// Hosts the four tabs and the floating bar. While something is selected the
/// navigation pill gives way to the selection bar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  void _select(WidgetRef ref, int i) {
    ref.read(selectionProvider.notifier).clear();
    // Tapping the current tab returns it to its first screen.
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SelectionState sel = ref.watch(selectionProvider);
    final double bottom =
        MediaQuery.paddingOf(context).bottom + AppNavMetrics.bottomGap;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: shell),
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
                    : FloatingNav(
                        key: const ValueKey<String>('nav'),
                        index: shell.currentIndex,
                        onSelect: (int i) => _select(ref, i),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Material "fade through" between tabs: the old tab fades out quickly, the
/// new one fades in while settling from 96% scale. Inactive tabs stay mounted
/// so each keeps its scroll position and navigation stack.
class FadeThroughBranches extends StatefulWidget {
  const FadeThroughBranches({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeThroughBranches> createState() => _FadeThroughBranchesState();
}

class _FadeThroughBranchesState extends State<FadeThroughBranches>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    value: 1,
  );
  int? _previous;

  @override
  void didUpdateWidget(FadeThroughBranches old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _previous = old.index;
      final bool reduce = MediaQuery.of(context).disableAnimations;
      _c.forward(from: reduce ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> fadeOut = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.3, curve: AppMotion.accelerate),
    );
    final Animation<double> fadeIn = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.3, 1, curve: AppMotion.decelerate),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, _) {
        final bool animating = _c.isAnimating;
        return Stack(
          children: <Widget>[
            for (int i = 0; i < widget.children.length; i++)
              _branch(i, animating, fadeIn, fadeOut),
          ],
        );
      },
    );
  }

  Widget _branch(
    int i,
    bool animating,
    Animation<double> fadeIn,
    Animation<double> fadeOut,
  ) {
    final bool current = i == widget.index;
    final bool leaving = animating && i == _previous;
    final Widget child = widget.children[i];
    if (current) {
      return Positioned.fill(
        child: Opacity(
          opacity: fadeIn.value,
          child: Transform.scale(
            scale: 0.96 + 0.04 * fadeIn.value,
            child: child,
          ),
        ),
      );
    }
    return Positioned.fill(
      child: Offstage(
        offstage: !leaving,
        child: TickerMode(
          enabled: leaving,
          child: IgnorePointer(
            child: Opacity(opacity: 1 - fadeOut.value, child: child),
          ),
        ),
      ),
    );
  }
}
