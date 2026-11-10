import 'package:flutter/material.dart';

/// Marks a page the user opened (not a tab), so its first rows can slide up
/// in a short stagger while it arrives. Rows built after the arrival, such
/// as those scrolled into view later, appear without motion.
class EntranceScope extends StatefulWidget {
  const EntranceScope({super.key, required this.child});

  final Widget child;

  /// How long after opening rows may still animate in.
  static const Duration window = Duration(milliseconds: 500);

  @override
  State<EntranceScope> createState() => _EntranceScopeState();
}

class _EntranceScopeState extends State<EntranceScope> {
  final Stopwatch _since = Stopwatch()..start();

  @override
  Widget build(BuildContext context) =>
      _EntranceClock(since: _since, child: widget.child);
}

class _EntranceClock extends InheritedWidget {
  const _EntranceClock({required this.since, required super.child});

  final Stopwatch since;

  @override
  bool updateShouldNotify(_EntranceClock old) => false;
}

/// Slides [child] up 16 pt and fades it in, [index] steps of 30 ms after the
/// page opened. Does nothing outside an [EntranceScope], past the first
/// dozen rows, after the opening window, or with animations turned off.
class SlideUpIn extends StatefulWidget {
  const SlideUpIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<SlideUpIn> createState() => _SlideUpInState();
}

class _SlideUpInState extends State<SlideUpIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final _EntranceClock? clock = context
        .getInheritedWidgetOfExactType<_EntranceClock>();
    final bool animate =
        clock != null &&
        widget.index < 12 &&
        clock.since.elapsed < EntranceScope.window &&
        !MediaQuery.disableAnimationsOf(context);
    if (!animate) return;
    // The stagger is a lead-in inside one animation, so no timer is needed.
    _c = AnimationController(vsync: this, duration: _lead + _run)..forward();
  }

  static const Duration _run = Duration(milliseconds: 380);
  Duration get _lead => Duration(milliseconds: 30 * widget.index);

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AnimationController? c = _c;
    if (c == null) return widget.child;
    final double start = _lead.inMicroseconds / c.duration!.inMicroseconds;
    final Animation<double> t = CurvedAnimation(
      parent: c,
      curve: Interval(start, 1, curve: const Cubic(0.23, 1, 0.32, 1)),
    );
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        builder: (BuildContext context, Widget? child) => Transform.translate(
          offset: Offset(0, 16 * (1 - t.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// [children] with each one sliding up in turn; for a page's fixed list.
List<Widget> staggered(List<Widget> children) => <Widget>[
  for (final (int i, Widget w) in children.indexed)
    SlideUpIn(index: i, child: w),
];
