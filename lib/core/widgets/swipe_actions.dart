import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';
import '../theme/app_tokens.dart';

/// A button revealed by swiping a row to the left.
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Red, for an action that deletes.
  final bool destructive;
}

const double _actionWidth = 76;

/// A row that slides left to reveal [actions], as in iOS lists. A flick or a
/// drag past half opens it; tapping the row while open closes it. [child]
/// must paint an opaque background, since the buttons sit behind it.
class SwipeActions extends StatefulWidget {
  const SwipeActions({super.key, required this.child, required this.actions});

  final Widget child;
  final List<SwipeAction> actions;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  /// 0 closed, 1 fully open.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
  );

  double get _width => _actionWidth * widget.actions.length;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _settle(bool open) {
    if (open && _open.value < 1) AppHaptics.tick();
    _open.animateTo(
      open ? 1 : 0,
      curve: AppMotion.decelerate,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.medium,
    );
  }

  void _run(SwipeAction a) {
    _settle(false);
    a.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              for (final SwipeAction a in widget.actions)
                SizedBox(
                  width: _actionWidth,
                  child: Material(
                    color: a.destructive ? cs.error : cs.onSurfaceVariant,
                    child: InkWell(
                      onTap: () => _run(a),
                      child: Center(
                        child: Text(
                          a.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: a.destructive ? cs.onError : cs.surface,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        GestureDetector(
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              _open.value -= (d.primaryDelta ?? 0) / _width,
          onHorizontalDragEnd: (DragEndDetails d) {
            final double v = d.primaryVelocity ?? 0;
            _settle(v < -300 || (v <= 300 && _open.value > 0.5));
          },
          child: AnimatedBuilder(
            animation: _open,
            builder: (BuildContext context, Widget? child) =>
                Transform.translate(
                  offset: Offset(-_open.value * _width, 0),
                  child: Stack(
                    children: <Widget>[
                      child!,
                      // While open, a tap on the row closes it instead of
                      // opening the file.
                      if (_open.value > 0)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _settle(false),
                          ),
                        ),
                    ],
                  ),
                ),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
