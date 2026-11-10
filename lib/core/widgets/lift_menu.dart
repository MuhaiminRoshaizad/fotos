import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';
import '../theme/app_tokens.dart';

/// One choice in a [showLiftMenu].
class LiftAction<T> {
  const LiftAction(
    this.value,
    this.label,
    this.icon, {
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;

  /// Drawn in red: deletes something.
  final bool destructive;
}

/// iOS's press-and-hold menu: the thing held lifts out of its place at
/// [from] (in global coordinates) into a larger [preview], the page blurs
/// behind it, and a short menu opens underneath. Returns the chosen value,
/// or null when dismissed by a tap outside or the back gesture.
///
/// [preview] must look right at any size between [from] and a box of
/// [aspectRatio] (width over height); an image with `BoxFit.cover` does.
Future<T?> showLiftMenu<T>(
  BuildContext context, {
  required Rect from,
  required double aspectRatio,
  required Widget preview,
  required List<LiftAction<T>> actions,
  double fromRadius = 0,
}) {
  AppHaptics.longPress();
  return Navigator.of(context, rootNavigator: true).push<T>(
    _LiftRoute<T>(
      from: from,
      aspectRatio: aspectRatio,
      preview: preview,
      actions: actions,
      fromRadius: fromRadius,
    ),
  );
}

class _LiftRoute<T> extends PopupRoute<T> {
  _LiftRoute({
    required this.from,
    required this.aspectRatio,
    required this.preview,
    required this.actions,
    required this.fromRadius,
  });

  final Rect from;
  final double aspectRatio;
  final Widget preview;
  final List<LiftAction<T>> actions;
  final double fromRadius;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _LiftPage<T>(route: this, animation: animation);
}

class _LiftPage<T> extends StatelessWidget {
  const _LiftPage({required this.route, required this.animation});

  final _LiftRoute<T> route;
  final Animation<double> animation;

  static const double _rowHeight = 46;
  static const double _gap = 12;
  static const double _margin = 24;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final bool still = MediaQuery.disableAnimationsOf(context);
    final double menuHeight = route.actions.length * _rowHeight;

    // The preview as large as fits above its menu, at the thing's own shape.
    final double roomH =
        screen.height - safe.vertical - 2 * _margin - _gap - menuHeight;
    double w = math.min(screen.width - 2 * _margin, 420);
    double h = w / route.aspectRatio;
    if (h > roomH) {
      h = math.max(roomH, 80);
      w = h * route.aspectRatio;
    }
    final double total = h + _gap + menuHeight;
    final double top = math.max(
      safe.top + _margin,
      (screen.height - total) / 2,
    );
    final Rect target = Rect.fromLTWH((screen.width - w) / 2, top, w, h);
    final double menuWidth = math.min(250, screen.width - 2 * _margin);
    // Under the preview's left edge, pulled in if it would leave the screen.
    final double menuLeft = math
        .min(target.left, screen.width - _margin - menuWidth)
        .clamp(_margin, double.infinity);

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, _) {
        final double t = animation.value;
        final double m = still ? 1 : Curves.easeOutBack.transform(t);
        final Rect rect = still ? target : Rect.lerp(route.from, target, m)!;
        return Stack(
          children: <Widget>[
            // Taps here fall through to the route's barrier, which dismisses.
            Positioned.fill(
              child: IgnorePointer(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 0.01 + 18 * t,
                    sigmaY: 0.01 + 18 * t,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.32 * t),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: Opacity(
                opacity: still ? t : 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      route.fromRadius + (AppRadii.lg - route.fromRadius) * t,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4 * t),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      route.fromRadius + (AppRadii.lg - route.fromRadius) * t,
                    ),
                    child: route.preview,
                  ),
                ),
              ),
            ),
            Positioned(
              left: menuLeft,
              top: target.bottom + _gap,
              width: menuWidth,
              child: Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: still ? 1 : 0.6 + 0.4 * m,
                  alignment: Alignment.topLeft,
                  child: _Menu<T>(
                    actions: route.actions,
                    rowHeight: _rowHeight,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Menu<T> extends StatelessWidget {
  const _Menu({required this.actions, required this.rowHeight});

  final List<LiftAction<T>> actions;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Material(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.9),
          // Rows have a fixed height, so the text may not grow past it.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final (int i, LiftAction<T> a) in actions.indexed)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(a.value),
                    child: Container(
                      height: rowHeight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      decoration: BoxDecoration(
                        border: i == 0
                            ? null
                            : Border(
                                top: BorderSide(
                                  color: cs.outlineVariant,
                                  width: 0.5,
                                ),
                              ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              a.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                color: a.destructive ? cs.error : cs.onSurface,
                              ),
                            ),
                          ),
                          Icon(
                            a.icon,
                            size: AppIconSize.dense,
                            color: a.destructive ? cs.error : cs.onSurface,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
