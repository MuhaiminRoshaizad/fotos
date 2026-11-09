import 'dart:async';

import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';
import '../theme/app_tokens.dart';

/// The handle on the right edge for jumping through a long grid. It appears
/// while scrolling and, when dragged, shows the month (or year) under it.
class DateScrubber extends StatefulWidget {
  const DateScrubber({
    super.key,
    required this.controller,
    required this.labelAt,
  });

  final ScrollController controller;
  final String Function(double offset) labelAt;

  @override
  State<DateScrubber> createState() => _DateScrubberState();
}

class _DateScrubberState extends State<DateScrubber> {
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
  void didUpdateWidget(DateScrubber old) {
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

  void _dragTo(double dy, double trackHeight) {
    final ScrollPosition p = widget.controller.position;
    final double f = ((dy - _thumbHeight / 2) / (trackHeight - _thumbHeight))
        .clamp(0, 1);
    final double offset = f * p.maxScrollExtent;
    widget.controller.jumpTo(offset);
    final String label = widget.labelAt(offset);
    if (label != _label) {
      if (_label.isNotEmpty) AppHaptics.tick();
      setState(() => _label = label);
    }
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
                          label: 'Scroll by date',
                          slider: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragStart: (DragStartDetails d) {
                              _hide?.cancel();
                              setState(() {
                                _dragging = true;
                                _label = widget.labelAt(
                                  widget.controller.offset,
                                );
                              });
                            },
                            onVerticalDragUpdate: (DragUpdateDetails d) =>
                                _dragTo(top + d.localPosition.dy, track),
                            onVerticalDragEnd: (_) {
                              setState(() => _dragging = false);
                              _onScroll();
                            },
                            child: Container(
                              width: 32,
                              height: _thumbHeight,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    blurRadius: 8,
                                    color: Color(0x33000000),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.unfold_more,
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
