import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/platform/gesture_exclusion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/pinch_first.dart';
import '../domain/cut_plan.dart';
import '../domain/timeline_view.dart';
import 'cut_timeline_painter.dart';
import 'timeline_frames.dart';

/// The video's frames under the edit, with the playhead fixed in the middle:
/// the kept stretch framed in yellow, cut parts in red.
///
/// Dragging the strip scrolls the video under the playhead; a drag that
/// starts on a handle moves that handle instead; two fingers zoom, from the
/// whole video down to [TimelineView.finestSpan] across. A handle keeps the
/// spot under the finger it was taken by and stays where it is let go, and
/// nothing moves on its own after a finger lifts: no fling, no snapping.
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
  final TimelineFrames frames;

  /// The playhead, in ms of the original video.
  final int position;
  final Handle? selected;
  final int? selectedCut;
  final void Function(Handle handle, int ms) onMove;

  /// Moves the playhead: a scroll, or a tap on the strip.
  final ValueChanged<int> onScrub;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<Handle?> onSelect;
  final ValueChanged<int?> onSelectCut;

  static const double stripHeight = 56;

  /// How near a touch must land to take a handle.
  static const double reach = 24;

  /// How near an edge a dragged handle starts the strip scrolling.
  static const double edge = 40;

  @override
  State<CutTimeline> createState() => CutTimelineState();
}

class CutTimelineState extends State<CutTimeline> {
  final GlobalKey _box = GlobalKey();
  double _width = 1;
  TimelineView? _view;

  /// The view now: what the strip shows.
  TimelineView get view => _view!;

  // A handle being dragged, where on it the finger took hold, and the
  // finger's last place, for scrolling along at an edge.
  Handle? _handle;
  double _grab = 0;
  double _fingerX = 0;
  Timer? _edgeScroll;

  // A scroll: where it began.
  double _scrollFrom = 0;
  double _scrollCentre = 0;

  // A pinch: the zoom it began at.
  double _pinchFrom = 1;

  @override
  void didUpdateWidget(CutTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The strip follows the playhead (playback, a seek), except while a
    // handle is held: the strip stays still under the finger then, though
    // the picture shows the frame at the handle.
    if (_handle == null &&
        _view != null &&
        widget.position != oldWidget.position) {
      _view = _view!.at(widget.position);
    }
  }

  @override
  void dispose() {
    _edgeScroll?.cancel();
    GestureExclusion.set(this, null, 1);
    super.dispose();
  }

  /// Keeps Android's back swipe off the timeline: a handle dragged to a
  /// screen edge to scroll along would otherwise leave the editor.
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

  /// The handle a touch at [x] takes: the nearest within reach, the
  /// selected one first when two sit together.
  Handle? _handleAt(double x) {
    Handle? best;
    double bestGap = CutTimeline.reach;
    for (final Handle h in widget.plan.handles) {
      final double gap = (x - view.xOf(widget.plan.at(h), _width)).abs();
      final bool tie = (gap - bestGap).abs() < 1;
      if (gap < bestGap || (tie && h == widget.selected)) {
        best = h;
        bestGap = gap;
      }
    }
    return best;
  }

  void _dragStart(DragStartDetails d) {
    final double x = d.localPosition.dx;
    final Handle? h = _handleAt(x);
    widget.onDragStart();
    if (h == null) {
      _scrollFrom = x;
      _scrollCentre = view.centre;
      return;
    }
    _handle = h;
    _grab = view.xOf(widget.plan.at(h), _width) - x;
    _fingerX = x;
    widget.onSelect(h);
  }

  void _dragUpdate(DragUpdateDetails d) {
    final double x = d.localPosition.dx;
    final Handle? h = _handle;
    if (h == null) {
      // The strip moves with the finger: drag right to go back in time.
      final double centre = _scrollCentre - (x - _scrollFrom) * view.msPerPoint;
      setState(() => _view = view.at(centre));
      widget.onScrub(view.centre.round());
      return;
    }
    _fingerX = x;
    widget.onMove(h, view.msAt(x + _grab, _width));
    _scrollAtEdge();
  }

  void _dragEnd() {
    _edgeScroll?.cancel();
    _edgeScroll = null;
    final bool wasHandle = _handle != null;
    _handle = null;
    // Back to the frame under the playhead, which hasn't moved.
    if (wasHandle) widget.onScrub(view.centre.round());
    widget.onDragEnd();
  }

  void _dragEnded(DragEndDetails _) => _dragEnd();

  /// While a held handle is near an edge, the strip scrolls that way, the
  /// faster the nearer, carrying the handle along under the finger.
  void _scrollAtEdge() {
    final double gap = _fingerX < CutTimeline.edge
        ? -(CutTimeline.edge - _fingerX)
        : _fingerX > _width - CutTimeline.edge
        ? _fingerX - (_width - CutTimeline.edge)
        : 0;
    if (gap == 0) {
      _edgeScroll?.cancel();
      _edgeScroll = null;
      return;
    }
    _edgeScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final Handle? h = _handle;
      if (!mounted || h == null) return;
      final double g = _fingerX < CutTimeline.edge
          ? -(CutTimeline.edge - _fingerX)
          : _fingerX > _width - CutTimeline.edge
          ? _fingerX - (_width - CutTimeline.edge)
          : 0;
      if (g == 0) return;
      // Up to 12 points a frame at the very edge.
      final double points = g / CutTimeline.edge * 12;
      setState(() => _view = view.at(view.centre + points * view.msPerPoint));
      widget.onMove(h, view.msAt(_fingerX + _grab, _width));
    });
  }

  void _pinchStart(ScaleStartDetails d) => _pinchFrom = view.msPerPoint;

  void _pinchUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount < 2 || d.scale <= 0) return;
    setState(() => _view = view.zoomed(_pinchFrom / d.scale, _width));
  }

  void _tap(TapUpDetails d) {
    final double x = d.localPosition.dx;
    final Handle? h = _handleAt(x);
    if (h != null) {
      widget.onSelect(h);
      return;
    }
    final int ms = view.msAt(x, _width).clamp(0, widget.plan.duration);
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
        _width = c.maxWidth <= 0 ? 1 : c.maxWidth;
        // Following the playhead happens in didUpdateWidget, which leaves
        // the strip still while a handle is held; here the zoom is only
        // kept within what this width allows.
        final TimelineView v = _view = _view == null
            ? TimelineView.fit(widget.plan.duration, _width).at(widget.position)
            : _view!.zoomed(_view!.msPerPoint, _width);
        widget.frames.want(FrameTiles.needed(v, _width));
        return Semantics(
          label: 'Timeline',
          child: RawGestureDetector(
            key: _box,
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer
                  >(
                    HorizontalDragGestureRecognizer.new,
                    (HorizontalDragGestureRecognizer r) => r
                      // From the touch itself, so a handle takes hold
                      // where the finger landed.
                      ..dragStartBehavior = DragStartBehavior.down
                      ..onStart = _dragStart
                      ..onUpdate = _dragUpdate
                      ..onEnd = _dragEnded
                      ..onCancel = _dragEnd,
                  ),
              PinchFirst: GestureRecognizerFactoryWithHandlers<PinchFirst>(
                () => PinchFirst(oneFinger: () => false),
                (PinchFirst r) => r
                  ..onStart = _pinchStart
                  ..onUpdate = _pinchUpdate,
              ),
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (TapGestureRecognizer r) => r..onTapUp = _tap,
                  ),
            },
            child: SizedBox(
              height: CutTimeline.stripHeight + 2 * AppSpacing.md,
              child: ListenableBuilder(
                listenable: widget.frames,
                builder: (BuildContext context, _) => Stack(
                  children: <Widget>[
                    Positioned(
                      left: 0,
                      right: 0,
                      top: AppSpacing.md,
                      height: CutTimeline.stripHeight,
                      child: FrameTiles(
                        view: view,
                        frames: widget.frames,
                        width: _width,
                        height: CutTimeline.stripHeight,
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: EditPainter(
                          plan: widget.plan,
                          view: view,
                          selected: widget.selected,
                          selectedCut: widget.selectedCut,
                          top: AppSpacing.md,
                          height: CutTimeline.stripHeight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
