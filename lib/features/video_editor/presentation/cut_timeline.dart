import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/haptics/app_haptics.dart';
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
    required this.playing,
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

  /// While playing the strip follows the playhead exactly; a jump made
  /// otherwise (a tap, a typed time, Start here) glides there instead.
  final bool playing;
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

class CutTimelineState extends State<CutTimeline>
    with TickerProviderStateMixin {
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

  // Where a finger is in charge, things follow it exactly; otherwise a
  // change glides. A scroll in progress:
  bool _scrolling = false;

  // A change to the plan made by a button, gliding from how it looked.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: AppMotion.short,
  )..addListener(_redraw);
  PlanShape? _shapeFrom;

  // A change of selection, cross-fading.
  late final AnimationController _selecting = AnimationController(
    vsync: this,
    duration: AppMotion.short,
    value: 1,
  )..addListener(_redraw);
  Handle? _previous;
  int? _previousCut;

  // A jump of the playhead, gliding the strip there.
  late final AnimationController _seek =
      AnimationController(
        vsync: this,
        duration: AppMotion.short,
      )..addListener(() {
        final double t = Curves.easeOut.transform(_seek.value);
        setState(() => _view = view.at(_seekFrom + (_seekTo - _seekFrom) * t));
      });
  double _seekFrom = 0;
  double _seekTo = 0;

  // Whether a dragged handle, or a pinch, is held at a limit: the tick is
  // felt once on reaching it, not on every move past it.
  bool _atStop = false;
  bool _zoomStop = false;

  void _redraw() => setState(() {});

  /// The plan as drawn for [target]: [target] itself, or on its way there.
  PlanShape _shapeFor(CutPlan target) {
    final PlanShape to = PlanShape.of(target);
    final PlanShape? from = _shapeFrom;
    if (from == null || !_settle.isAnimating) return to;
    return PlanShape.lerp(from, to, Curves.easeOut.transform(_settle.value));
  }

  /// Stops a glide of the strip where it was going.
  void _settleSeek() {
    if (!_seek.isAnimating) return;
    _seek.stop();
    _view = view.at(_seekTo);
  }

  @override
  void didUpdateWidget(CutTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool still = MediaQuery.disableAnimationsOf(context);
    // A plan changed by a button (Start here, a step, a typed time, a new
    // or kept cut) glides there; a handle under a finger follows it.
    if (widget.plan != oldWidget.plan && _handle == null && !still) {
      _shapeFrom = _shapeFor(oldWidget.plan);
      _settle.forward(from: 0);
    }
    if (widget.selected != oldWidget.selected ||
        widget.selectedCut != oldWidget.selectedCut) {
      _previous = oldWidget.selected;
      _previousCut = oldWidget.selectedCut;
      still ? _selecting.value = 1 : _selecting.forward(from: 0);
    }
    // The strip follows the playhead, except while a handle is held: it
    // stays still under the finger then, though the picture shows the
    // frame at the handle. Playback and a scroll move it exactly; any
    // other jump glides.
    if (_handle == null &&
        _view != null &&
        widget.position != oldWidget.position) {
      if (_scrolling || widget.playing || still) {
        _seek.stop();
        _view = _view!.at(widget.position);
      } else {
        _seekFrom = view.centre;
        _seekTo = widget.position.toDouble();
        _seek.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    _selecting.dispose();
    _seek.dispose();
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
    _settleSeek();
    widget.onDragStart();
    if (h == null) {
      _scrolling = true;
      _scrollFrom = x;
      _scrollCentre = view.centre;
      return;
    }
    _atStop = false;
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
    _moveHandle(h, view.msAt(x + _grab, _width));
    _scrollAtEdge();
  }

  /// Moves [h] toward [ms]; a tick is felt as it reaches a neighbour or an
  /// end of the video and stops there.
  void _moveHandle(Handle h, int ms) {
    final bool stopped = widget.plan.move(h, ms).at(h) != ms;
    if (stopped && !_atStop) AppHaptics.tick();
    _atStop = stopped;
    widget.onMove(h, ms);
  }

  void _dragEnd() {
    _edgeScroll?.cancel();
    _edgeScroll = null;
    final bool wasHandle = _handle != null;
    _handle = null;
    _scrolling = false;
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
      _moveHandle(h, view.msAt(_fingerX + _grab, _width));
    });
  }

  void _pinchStart(ScaleStartDetails d) {
    _settleSeek();
    _pinchFrom = view.msPerPoint;
    _zoomStop = false;
  }

  void _pinchUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount < 2 || d.scale <= 0) return;
    final double wanted = _pinchFrom / d.scale;
    final TimelineView next = view.zoomed(wanted, _width);
    // A tick on reaching all the way in or out, as the grid's zoom steps.
    final bool stopped = next.msPerPoint != wanted;
    if (stopped && !_zoomStop) AppHaptics.tick();
    _zoomStop = stopped;
    setState(() => _view = next);
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
                          plan: _shapeFor(widget.plan),
                          view: view,
                          selected: widget.selected,
                          selectedCut: widget.selectedCut,
                          previous: _previous,
                          previousCut: _previousCut,
                          selecting: _selecting.value,
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
