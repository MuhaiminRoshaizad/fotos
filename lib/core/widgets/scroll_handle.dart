import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../haptics/app_haptics.dart';
import '../platform/gesture_exclusion.dart';
import '../theme/app_tokens.dart';

/// What the handle's bubble says about a spot in the list: [primary] large,
/// [secondary] small under it, and the [mark] on the track it belongs to.
@immutable
class HandleLabel {
  const HandleLabel(this.primary, {this.secondary, this.mark});

  static const HandleLabel none = HandleLabel('');

  final String primary;
  final String? secondary;
  final String? mark;

  bool get isEmpty => primary.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is HandleLabel &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.mark == mark;

  @override
  int get hashCode => Object.hash(primary, secondary, mark);
}

/// A step shown along the track while dragging: [text] beside the scroll
/// [offset] where that step starts.
@immutable
class HandleMark {
  const HandleMark(this.offset, this.text);

  final double offset;
  final String text;
}

/// The handle on the right edge for jumping through a long list. It appears
/// while scrolling; held, it grows, a bubble names what is under it, and
/// the list's steps (years, letters, sizes) line the track to aim at. It
/// stops where it is let go, with no momentum: it is for landing on a spot.
class ScrollHandle extends StatefulWidget {
  const ScrollHandle({
    super.key,
    required this.controller,
    required this.labelAt,
    required this.semanticLabel,
    this.marks,
  });

  final ScrollController controller;

  /// The label for the content at a scroll offset; [HandleLabel.none] shows
  /// no bubble.
  final HandleLabel Function(double offset) labelAt;

  /// What the handle scrolls by, for screen readers ("Scroll by date").
  final String semanticLabel;

  /// The steps to mark along the track, read when a drag begins; none when
  /// null.
  final List<HandleMark> Function()? marks;

  @override
  State<ScrollHandle> createState() => _ScrollHandleState();
}

class _ScrollHandleState extends State<ScrollHandle>
    with SingleTickerProviderStateMixin {
  // The touch area: wider and taller than the handle drawn in it, so a
  // grab slightly off still catches it (48 dp is the minimum touch size).
  static const double _slotWidth = 56;
  static const double _slotHeight = 72;
  static const Size _rest = Size(32, 48);
  static const Size _held = Size(46, 64);
  static const double _edge = 4;

  /// Marks closer than this to the one above are dropped.
  static const double _markGap = 16;

  late final AnimationController _grow = AnimationController.unbounded(
    vsync: this,
  );
  bool _visible = false;
  bool _dragging = false;
  HandleLabel _label = HandleLabel.none;
  List<HandleMark> _marks = const <HandleMark>[];
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ScrollHandle old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _hide?.cancel();
    _grow.dispose();
    GestureExclusion.set(this, null, 1);
    super.dispose();
  }

  bool get _worthShowing {
    if (!widget.controller.hasClients) return false;
    final ScrollPosition p = widget.controller.position;
    return p.maxScrollExtent > p.viewportDimension * 3;
  }

  void _onScroll() {
    if (!_worthShowing) return;
    _hide?.cancel();
    if (!_dragging) {
      _hide = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _visible = false);
      });
    }
    setState(() => _visible = true);
  }

  void _growTo(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _grow.value = target;
      return;
    }
    _grow.animateWith(
      SpringSimulation(AppMotion.spring, _grow.value, target, _grow.velocity),
    );
  }

  // Where the handle and the finger were when the drag began. The handle
  // then follows the finger 1:1: offsets measured from the handle itself
  // would count its own movement twice and run ahead of the finger.
  double _startTop = 0;
  double _startY = 0;

  void _start(double top, double globalY, double travel) {
    _hide?.cancel();
    _startTop = top;
    _startY = globalY;
    setState(() {
      _dragging = true;
      _label = widget.labelAt(widget.controller.offset);
      _marks = _place(widget.marks?.call() ?? const <HandleMark>[], travel);
    });
  }

  void _end() {
    _growTo(0);
    setState(() => _dragging = false);
    _onScroll();
  }

  /// Turns each mark's scroll offset into its height on the track, dropping
  /// any that would crowd the one above.
  List<HandleMark> _place(List<HandleMark> marks, double travel) {
    final double max = widget.controller.position.maxScrollExtent;
    if (max <= 0 || marks.length < 2) return const <HandleMark>[];
    final List<HandleMark> placed = <HandleMark>[];
    double last = double.negativeInfinity;
    for (final HandleMark m in marks) {
      final double y =
          (m.offset / max).clamp(0.0, 1.0) * travel + _slotHeight / 2;
      if (y - last < _markGap) continue;
      placed.add(HandleMark(y, m.text));
      last = y;
    }
    return placed.length < 2 ? const <HandleMark>[] : placed;
  }

  void _dragTo(double globalY, double travel) {
    final ScrollPosition p = widget.controller.position;
    if (travel <= 0) return;
    final double top = (_startTop + globalY - _startY).clamp(0, travel);
    widget.controller.jumpTo(top / travel * p.maxScrollExtent);
    _relabel();
  }

  bool _relabelling = false;

  /// Reads the label once the jump has been laid out, so a list can name
  /// the row it actually landed on rather than the one it left.
  void _relabel() {
    if (_relabelling) return;
    _relabelling = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _relabelling = false;
      if (!mounted || !_dragging || !widget.controller.hasClients) return;
      final HandleLabel label = widget.labelAt(widget.controller.offset);
      if (label != _label) {
        if (!_label.isEmpty) AppHaptics.tick();
        setState(() => _label = label);
      }
    });
  }

  final GlobalKey _slot = GlobalKey();
  double? _excludedTop;

  /// Keeps Android's back swipe off the touch area while the handle shows:
  /// it sits in the 30 dp strip down the right edge that Android otherwise
  /// keeps for going back, and a thumb drifting sideways lost the drag.
  void _exclude(double top) {
    if (!_visible) {
      _excludedTop = null;
      GestureExclusion.set(this, null, 1);
      return;
    }
    if (_excludedTop != null && (top - _excludedTop!).abs() < 8) return;
    _excludedTop = top;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final RenderBox? box =
          _slot.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || box == null || !box.attached || !_visible) return;
      GestureExclusion.set(
        this,
        box.localToGlobal(Offset.zero) & box.size,
        dpr,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextScaler scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.4);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double travel = c.maxHeight - _slotHeight;
        double top = 0;
        if (widget.controller.hasClients &&
            widget.controller.position.hasContentDimensions &&
            widget.controller.position.maxScrollExtent > 0) {
          final ScrollPosition p = widget.controller.position;
          top = (p.pixels / p.maxScrollExtent).clamp(0, 1) * travel;
        }
        _exclude(top);
        return IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: AppMotion.short,
            child: SizedBox(
              width: 220,
              height: c.maxHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _dragging && _marks.isNotEmpty ? 1 : 0,
                        duration: AppMotion.short,
                        child: Stack(
                          children: <Widget>[
                            for (final HandleMark m in _marks)
                              Positioned(
                                right: _slotWidth + AppSpacing.sm,
                                top: m.offset - 10,
                                height: 20,
                                child: _Mark(
                                  text: m.text,
                                  on: m.text == _label.mark,
                                  scaler: scaler,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: _slotWidth + AppSpacing.xs,
                    top: top,
                    height: _slotHeight,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedScale(
                          scale: _dragging && !_label.isEmpty ? 1 : 0.9,
                          duration: AppMotion.short,
                          curve: Curves.easeOutBack,
                          alignment: Alignment.centerRight,
                          child: AnimatedOpacity(
                            opacity: _dragging && !_label.isEmpty ? 1 : 0,
                            duration: AppMotion.short,
                            child: _Bubble(label: _label, scaler: scaler),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    key: _slot,
                    right: 0,
                    top: top,
                    width: _slotWidth,
                    height: _slotHeight,
                    child: Semantics(
                      label: widget.semanticLabel,
                      slider: true,
                      // Grows the moment it is touched, before the drag
                      // recognizer has seen enough movement to report.
                      child: Listener(
                        onPointerDown: (_) => _growTo(1),
                        onPointerUp: (_) {
                          if (!_dragging) _growTo(0);
                        },
                        onPointerCancel: (_) {
                          if (!_dragging) _growTo(0);
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: (DragStartDetails d) =>
                              _start(top, d.globalPosition.dy, travel),
                          onVerticalDragUpdate: (DragUpdateDetails d) =>
                              _dragTo(d.globalPosition.dy, travel),
                          onVerticalDragEnd: (_) => _end(),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: _edge),
                              child: AnimatedBuilder(
                                animation: _grow,
                                builder: (BuildContext context, Widget? icon) {
                                  final double g = _grow.value;
                                  final Size s = Size.lerp(_rest, _held, g)!;
                                  return Container(
                                    width: s.width,
                                    height: s.height,
                                    decoration: BoxDecoration(
                                      color: Color.lerp(
                                        cs.surfaceContainerLowest,
                                        cs.surfaceContainerHighest,
                                        g.clamp(0.0, 1.0),
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        s.width / 2,
                                      ),
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                          blurRadius:
                                              8 + 10 * g.clamp(0.0, 1.0),
                                          offset: Offset(0, 2 + 4 * g),
                                          color: const Color(0x33000000),
                                        ),
                                      ],
                                    ),
                                    child: icon,
                                  );
                                },
                                child: Icon(
                                  CupertinoIcons.chevron_up_chevron_down,
                                  size: AppIconSize.dense,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.label, required this.scaler});

  final HandleLabel label;
  final TextScaler scaler;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 6),
            color: Color(0x40000000),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.primary,
            textScaler: scaler,
            style: TextStyle(
              color: cs.onInverseSurface,
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          if (label.secondary != null)
            Text(
              label.secondary!,
              textScaler: scaler,
              style: TextStyle(
                color: cs.onInverseSurface.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.text, required this.on, required this.scaler});

  final String text;
  final bool on;
  final TextScaler scaler;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Text(
        text,
        textScaler: scaler.clamp(maxScaleFactor: 1.2),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: on ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
