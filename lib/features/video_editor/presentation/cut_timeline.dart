import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/platform/gesture_exclusion.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/cut_plan.dart';
import 'cut_timeline_painter.dart';

/// The video's frames under the edit: the kept stretch framed in yellow,
/// cut parts in red, and a white playhead.
///
/// A drag that starts on a handle moves that handle; anywhere else it moves
/// the playhead. The handle keeps the same spot under the finger from
/// touch-down to release, and stays exactly where it was let go: positions
/// come straight from the plan, which only changes when the finger moves.
class CutTimeline extends StatefulWidget {
  const CutTimeline({
    super.key,
    required this.plan,
    required this.frames,
    required this.position,
    required this.selected,
    required this.selectedCut,
    required this.onMove,
    required this.onScrub,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onSelect,
    required this.onSelectCut,
  });

  final CutPlan plan;

  /// Frames spread evenly across the video; null slots are still loading.
  final List<Uint8List?>? frames;

  /// The playhead, in ms of the original video.
  final int position;
  final Handle? selected;
  final int? selectedCut;
  final void Function(Handle handle, int ms) onMove;
  final ValueChanged<int> onScrub;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<Handle?> onSelect;
  final ValueChanged<int?> onSelectCut;

  /// Space either side of the strip, so the end handles sit inside the
  /// screen with room for a thumb.
  static const double inset = 24;
  static const double stripHeight = 56;

  /// How near a touch must land to take a handle.
  static const double reach = 24;

  @override
  State<CutTimeline> createState() => _CutTimelineState();
}

class _CutTimelineState extends State<CutTimeline> {
  final GlobalKey _box = GlobalKey();
  Handle? _dragging;

  /// Where on the handle the finger took hold, so it doesn't jump to
  /// centre itself under the finger.
  double _grab = 0;
  double _width = 1;

  @override
  void dispose() {
    GestureExclusion.set(this, null, 1);
    super.dispose();
  }

  /// Keeps Android's back swipe off the timeline: its end handles sit in
  /// the edge strips Android keeps for going back, and dragging one there
  /// would leave the editor.
  void _exclude() {
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final RenderBox? box =
          _box.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || box == null || !box.attached) return;
      GestureExclusion.set(
        this,
        box.localToGlobal(Offset.zero) & box.size,
        dpr,
      );
    });
  }

  double _x(int ms) => CutTimeline.inset + ms / widget.plan.duration * _width;

  int _ms(double x) =>
      ((x - CutTimeline.inset) / _width * widget.plan.duration).round();

  /// The handle a touch at [x] takes: the nearest within reach, the
  /// selected one first when two sit together.
  Handle? _handleAt(double x) {
    Handle? best;
    double bestGap = CutTimeline.reach;
    for (final Handle h in widget.plan.handles) {
      final double gap = (x - _x(widget.plan.at(h))).abs();
      final bool tie = (gap - bestGap).abs() < 1;
      if (gap < bestGap || (tie && h == widget.selected)) {
        best = h;
        bestGap = gap;
      }
    }
    return best;
  }

  void _down(DragStartDetails d) {
    final double x = d.localPosition.dx;
    final Handle? h = _handleAt(x);
    _dragging = h;
    widget.onDragStart();
    if (h == null) {
      widget.onScrub(_ms(x).clamp(0, widget.plan.duration));
      return;
    }
    _grab = _x(widget.plan.at(h)) - x;
    widget.onSelect(h);
  }

  void _update(DragUpdateDetails d) {
    final double x = d.localPosition.dx;
    final Handle? h = _dragging;
    if (h == null) {
      widget.onScrub(_ms(x).clamp(0, widget.plan.duration));
    } else {
      widget.onMove(h, _ms(x + _grab));
    }
  }

  void _up() {
    _dragging = null;
    widget.onDragEnd();
  }

  void _tap(TapUpDetails d) {
    final double x = d.localPosition.dx;
    final Handle? h = _handleAt(x);
    if (h != null) {
      widget.onSelect(h);
      return;
    }
    final int ms = _ms(x).clamp(0, widget.plan.duration);
    final int? cut = widget.plan.cutAt(ms);
    if (cut != null) {
      widget.onSelectCut(cut);
      return;
    }
    widget.onSelect(null);
    widget.onScrub(ms);
  }

  @override
  Widget build(BuildContext context) {
    _exclude();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        _width = (c.maxWidth - 2 * CutTimeline.inset).clamp(1, double.infinity);
        return Semantics(
          label: 'Timeline',
          child: GestureDetector(
            key: _box,
            behavior: HitTestBehavior.opaque,
            // From the touch itself, not from where the drag was first
            // recognised, so a handle takes hold where the finger landed.
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: _down,
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: (_) => _up(),
            onHorizontalDragCancel: _up,
            onTapUp: _tap,
            child: SizedBox(
              height: CutTimeline.stripHeight + 2 * AppSpacing.md,
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: CutTimeline.inset,
                    right: CutTimeline.inset,
                    top: AppSpacing.md,
                    height: CutTimeline.stripHeight,
                    child: TimelineFrames(frames: widget.frames),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: EditPainter(
                        plan: widget.plan,
                        position: widget.position,
                        selected: widget.selected,
                        selectedCut: widget.selectedCut,
                        inset: CutTimeline.inset,
                        top: AppSpacing.md,
                        height: CutTimeline.stripHeight,
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
