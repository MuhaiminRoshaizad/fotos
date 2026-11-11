import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/app_tokens.dart';

/// Small, shared pieces of motion for controls.
///
/// The rules they follow, so the app moves one way everywhere:
/// - Feedback lands on press-in, not on release: the control sinks under
///   the finger within about 100 ms.
/// - Whatever a finger moved comes back on a spring; everything else is a
///   short ease-out, under 300 ms.
/// - A change of state is shown where it happened: the glyph itself
///   swaps, pops or turns. Nothing else on the page moves for it.
/// - With "Remove animations" on, states still change but nothing travels.

/// A control that sinks a little when pressed and springs back when let go.
/// The tap is reported at once; the motion never delays it.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.label,
    required this.child,
    this.minSize = const Size(48, 44),
  });

  /// Null disables the control and dims it.
  final VoidCallback? onTap;

  /// Read by screen readers and shown as the tooltip.
  final String label;
  final Widget child;
  final Size minSize;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  void _down() {
    if (widget.onTap == null) return;
    _press.animateTo(
      1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _up() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _press.value = 0;
      return;
    }
    _press.animateWith(SpringSimulation(AppMotion.spring, _press.value, 0, 0));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        excludeSemantics: true,
        child: Listener(
          onPointerDown: (_) => _down(),
          onPointerUp: (_) => _up(),
          onPointerCancel: (_) => _up(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.minSize.width,
                minHeight: widget.minSize.height,
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: AnimatedBuilder(
                  animation: _press,
                  builder: (BuildContext context, Widget? child) {
                    final double v = _press.value;
                    return Opacity(
                      opacity: enabled ? (1 - 0.3 * v).clamp(0.0, 1.0) : 0.35,
                      child: Transform.scale(scale: 1 - 0.14 * v, child: child),
                    );
                  },
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Swaps one glyph for another by shrinking the old out and growing the new
/// in, in place. For a control whose icon is its state: play and pause,
/// sound on and off, an empty heart and a full one.
class GlyphSwap extends StatelessWidget {
  const GlyphSwap({super.key, required this.icon, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 200),
      reverseDuration: still
          ? Duration.zero
          : const Duration(milliseconds: 120),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1).animate(a),
          child: child,
        ),
      ),
      child: Icon(
        icon,
        key: ValueKey<IconData>(icon),
        size: size,
        color: color,
      ),
    );
  }
}

/// Swells its child once, past full size and back, each time [on] turns
/// true: the small celebration for adding a favourite or ticking a row.
class Pop extends StatefulWidget {
  const Pop({super.key, required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  State<Pop> createState() => _PopState();
}

class _PopState extends State<Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  static final Animatable<double> _swell =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: 1.32,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 35,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1.32,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 65,
        ),
      ]);

  @override
  void didUpdateWidget(Pop old) {
    super.didUpdateWidget(old);
    if (widget.on && !old.on && !MediaQuery.disableAnimationsOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _swell.animate(_c), child: widget.child);
}

/// A glyph that is dim while its setting is off and bright while it is on,
/// and makes one full turn as it comes on. Made for Loop, whose glyph is a
/// pair of arrows chasing each other: the turn is the setting, acted out.
class TurnOnGlyph extends StatefulWidget {
  const TurnOnGlyph({
    super.key,
    required this.icon,
    required this.on,
    this.size,
    this.color = Colors.white,
  });

  final IconData icon;
  final bool on;
  final double? size;
  final Color color;

  @override
  State<TurnOnGlyph> createState() => _TurnOnGlyphState();
}

class _TurnOnGlyphState extends State<TurnOnGlyph> {
  int _turns = 0;

  @override
  void didUpdateWidget(TurnOnGlyph old) {
    super.didUpdateWidget(old);
    if (widget.on && !old.on) _turns++;
  }

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.disableAnimationsOf(context);
    return AnimatedOpacity(
      opacity: widget.on ? 1 : 0.38,
      duration: still ? Duration.zero : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedRotation(
        turns: _turns.toDouble(),
        duration: still ? Duration.zero : const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        child: Pop(
          on: widget.on,
          child: Icon(widget.icon, size: widget.size, color: widget.color),
        ),
      ),
    );
  }
}
