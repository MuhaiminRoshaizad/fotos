import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../haptics/app_haptics.dart';
import '../theme/app_tokens.dart';

/// The handle on the right edge for jumping through a long list. It appears
/// while scrolling and, when dragged, shows a label for what is under it:
/// the month on Photos, the page in a comic, the letter in a folder.
class ScrollHandle extends StatefulWidget {
  const ScrollHandle({
    super.key,
    required this.controller,
    required this.labelAt,
    required this.semanticLabel,
  });

  final ScrollController controller;

  /// The label for the content at a scroll offset; empty shows none.
  final String Function(double offset) labelAt;

  /// What the handle scrolls by, for screen readers ("Scroll by date").
  final String semanticLabel;

  @override
  State<ScrollHandle> createState() => _ScrollHandleState();
}

class _ScrollHandleState extends State<ScrollHandle> {
  static const double _thumbHeight = 48;
  bool _visible = false;
  bool _dragging = false;
  String _label = '';
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

  // Where the handle and the finger were when the drag began. The handle
  // then follows the finger 1:1: offsets measured from the handle itself
  // would count its own movement twice and run ahead of the finger.
  double _startTop = 0;
  double _startY = 0;

  void _dragTo(double globalY, double trackHeight) {
    final ScrollPosition p = widget.controller.position;
    final double travel = trackHeight - _thumbHeight;
    if (travel <= 0) return;
    final double thumbTop = (_startTop + globalY - _startY).clamp(0, travel);
    final double offset = thumbTop / travel * p.maxScrollExtent;
    widget.controller.jumpTo(offset);
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
      final String label = widget.labelAt(widget.controller.offset);
      if (label != _label) {
        if (_label.isNotEmpty) AppHaptics.tick();
        setState(() => _label = label);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double track = c.maxHeight;
        double top = 0;
        if (widget.controller.hasClients &&
            widget.controller.position.hasContentDimensions &&
            widget.controller.position.maxScrollExtent > 0) {
          final ScrollPosition p = widget.controller.position;
          top =
              (p.pixels / p.maxScrollExtent).clamp(0, 1) *
              (track - _thumbHeight);
        }
        return IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: AppMotion.short,
            child: SizedBox(
              width: 160,
              height: track,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    right: 4,
                    top: top,
                    child: Row(
                      children: <Widget>[
                        if (_dragging && _label.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(right: AppSpacing.sm),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: cs.inverseSurface,
                              borderRadius: BorderRadius.circular(AppRadii.md),
                            ),
                            child: Text(
                              _label,
                              style: TextStyle(
                                color: cs.onInverseSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Semantics(
                          label: widget.semanticLabel,
                          slider: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragStart: (DragStartDetails d) {
                              _hide?.cancel();
                              _startTop = top;
                              _startY = d.globalPosition.dy;
                              setState(() {
                                _dragging = true;
                                _label = widget.labelAt(
                                  widget.controller.offset,
                                );
                              });
                            },
                            onVerticalDragUpdate: (DragUpdateDetails d) =>
                                _dragTo(d.globalPosition.dy, track),
                            onVerticalDragEnd: (_) {
                              setState(() => _dragging = false);
                              _onScroll();
                            },
                            child: Container(
                              width: 32,
                              height: _thumbHeight,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.lg,
                                ),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    blurRadius: 8,
                                    color: Color(0x33000000),
                                  ),
                                ],
                              ),
                              child: Icon(
                                CupertinoIcons.chevron_up_chevron_down,
                                size: AppIconSize.dense,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
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
