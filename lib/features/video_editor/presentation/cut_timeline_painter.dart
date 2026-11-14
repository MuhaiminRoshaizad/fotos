import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../domain/cut_plan.dart';
import '../domain/timeline_view.dart';
import 'timeline_frames.dart';

// The editor is always dark, as the viewer is. iOS's own system yellow and
// red, the colours its trim and destructive controls use.
const Color editYellow = Color(0xFFFFD60A);
const Color editRed = Color(0xFFFF3B30);

/// The video's frames along the strip for the stretch in [view]: one tile
/// per round step of time, each showing the frame from its middle, or the
/// nearest frame read so far while its own loads.
class FrameTiles extends StatelessWidget {
  const FrameTiles({
    super.key,
    required this.view,
    required this.frames,
    required this.width,
    required this.height,
  });

  final TimelineView view;
  final TimelineFrames frames;
  final double width;
  final double height;

  /// The narrowest a tile gets; frames are portrait-ish thumbnails.
  static const double minTile = 40;

  /// The middle of each tile on screen, in ms: the frames [view] needs.
  static List<int> needed(TimelineView view, double width) {
    final int step = view.tileStep(minTile);
    final int first = (view.msAt(0, width) / step).floor().clamp(0, 1 << 30);
    final int last = (view.msAt(width, width) / step).ceil();
    return <int>[
      for (int i = first; i <= last; i++)
        if (i * step < view.duration) _middle(i, step, view.duration),
    ];
  }

  static int _middle(int i, int step, int duration) {
    final int end = (i + 1) * step < duration ? (i + 1) * step : duration;
    return (i * step + end) ~/ 2;
  }

  @override
  Widget build(BuildContext context) {
    final int step = view.tileStep(minTile);
    final int first = (view.msAt(0, width) / step).floor().clamp(0, 1 << 30);
    final int last = (view.msAt(width, width) / step).ceil();
    final bool still = MediaQuery.disableAnimationsOf(context);
    final double left = view.xOf(0, width);
    final double right = view.xOf(view.duration, width);
    return ClipRect(
      child: Stack(
        children: <Widget>[
          // The video's own extent, dark until its frames arrive.
          Positioned(
            left: left,
            width: right - left,
            top: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: const ColoredBox(color: Color(0xFF2C2C2E)),
            ),
          ),
          for (int i = first; i <= last; i++)
            if (i * step < view.duration)
              _tile(i, step, view.xOf(i * step, width), still),
        ],
      ),
    );
  }

  Widget _tile(int i, int step, double x, bool still) {
    final int end = (i + 1) * step < view.duration
        ? (i + 1) * step
        : view.duration;
    final double w = view.xOf(end, width) - x;
    final Widget image = switch (frames.frameNear(
      _middle(i, step, view.duration),
    )) {
      null => const SizedBox.expand(),
      final f => Image.memory(
        f,
        key: ObjectKey(f),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
      ),
    };
    return Positioned(
      left: x,
      width: w,
      top: 0,
      height: height,
      // A frame fades in over the stand-in it replaces.
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: still ? Duration.zero : AppMotion.short,
          child: image,
        ),
      ),
    );
  }
}

/// A plan as drawn: its ends and cuts in fractional ms, so a change made
/// by a button can glide from where it was to where it is, a new cut
/// growing from its middle and a kept one shrinking into it.
@immutable
class PlanShape {
  const PlanShape(this.duration, this.start, this.end, this.cuts);

  factory PlanShape.of(CutPlan p) => PlanShape(
    p.duration,
    p.start.toDouble(),
    p.end.toDouble(),
    <(double, double)>[
      for (final Span c in p.cuts) (c.start.toDouble(), c.end.toDouble()),
    ],
  );

  final int duration;
  final double start;
  final double end;
  final List<(double, double)> cuts;

  /// Between [a] and [b], [t] of the way.
  static PlanShape lerp(PlanShape a, PlanShape b, double t) {
    List<(double, double)> from = a.cuts;
    List<(double, double)> to = b.cuts;
    if (from.length + 1 == to.length) from = _gapFor(from, to);
    if (to.length + 1 == from.length) to = _gapFor(to, from);
    if (from.length != to.length) return t < 0.5 ? a : b;
    double l(double x, double y) => x + (y - x) * t;
    return PlanShape(
      b.duration,
      l(a.start, b.start),
      l(a.end, b.end),
      <(double, double)>[
        for (int i = 0; i < to.length; i++)
          (l(from[i].$1, to[i].$1), l(from[i].$2, to[i].$2)),
      ],
    );
  }

  /// [fewer] with a cut of no width in the middle of the one [more] has
  /// that it lacks.
  static List<(double, double)> _gapFor(
    List<(double, double)> fewer,
    List<(double, double)> more,
  ) {
    int i = 0;
    while (i < fewer.length && fewer[i] == more[i]) {
      i++;
    }
    final double mid = (more[i].$1 + more[i].$2) / 2;
    return <(double, double)>[...fewer]..insert(i, (mid, mid));
  }
}

/// Everything drawn over the frames: what is left out, the yellow frame
/// and grips round what is kept, the cut handles, and the playhead fixed in
/// the middle.
class EditPainter extends CustomPainter {
  EditPainter({
    required this.plan,
    required this.view,
    required this.selected,
    required this.selectedCut,
    required this.previous,
    required this.previousCut,
    required this.selecting,
    required this.top,
    required this.height,
  });

  final PlanShape plan;
  final TimelineView view;
  final Handle? selected;
  final int? selectedCut;

  /// What was selected before, fading out as [selected] fades in.
  final Handle? previous;
  final int? previousCut;

  /// How far the change of selection has got, 0 to 1.
  final double selecting;
  final double top;
  final double height;

  /// How lit [h] is: 1 selected, 0 not, between while selection moves.
  double _lit(Handle h) => h == selected
      ? selecting
      : h == previous
      ? 1 - selecting
      : 0;

  double _litCut(int i) => i == selectedCut
      ? selecting
      : i == previousCut
      ? 1 - selecting
      : 0;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    double x(num ms) => view.xOf(ms, w);
    final double bottom = top + height;
    Rect band(num from, num to) => Rect.fromLTRB(x(from), top, x(to), bottom);

    // What is left out: dimmed outside the ends, red where cut.
    final Paint dim = Paint()..color = const Color(0xB3000000);
    canvas.drawRect(band(0, plan.start), dim);
    canvas.drawRect(band(plan.end, plan.duration), dim);
    for (int i = 0; i < plan.cuts.length; i++) {
      final (double from, double to) = plan.cuts[i];
      final Rect r = band(from, to);
      canvas.drawRect(r, dim);
      canvas.drawRect(
        r,
        Paint()..color = editRed.withValues(alpha: 0.35 + 0.2 * _litCut(i)),
      );
      _cutHandle(canvas, r.left, Handle.cutStart(i));
      _cutHandle(canvas, r.right, Handle.cutEnd(i));
    }

    // The kept stretch, framed in yellow with a grip at each end.
    final double l = x(plan.start);
    final double r = x(plan.end);
    final Paint yellow = Paint()..color = editYellow;
    canvas.drawRect(Rect.fromLTRB(l, top - 3, r, top), yellow);
    canvas.drawRect(Rect.fromLTRB(l, bottom, r, bottom + 3), yellow);
    _endHandle(canvas, l - 12, l, _lit(const Handle.start()));
    _endHandle(canvas, r, r + 12, _lit(const Handle.end()));

    // The playhead, fixed in the middle, over everything.
    final double p = w / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(p - 1.5, top - 6, p + 1.5, bottom + 6),
        const Radius.circular(1.5),
      ),
      Paint()..color = Colors.white,
    );
  }

  void _endHandle(Canvas canvas, double left, double right, double lit) {
    final RRect grip = RRect.fromRectAndRadius(
      Rect.fromLTRB(left, top - 3, right, top + height + 3),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      grip,
      Paint()..color = Color.lerp(editYellow, Colors.white, lit)!,
    );
    final double mid = (left + right) / 2;
    canvas.drawLine(
      Offset(mid, top + height / 2 - 8),
      Offset(mid, top + height / 2 + 8),
      Paint()
        ..color = Colors.black54
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _cutHandle(Canvas canvas, double at, Handle h) {
    final double lit = _lit(h);
    final Paint white = Paint()
      ..color = Color.lerp(const Color(0xE6FFFFFF), Colors.white, lit)!;
    canvas.drawRect(
      Rect.fromLTRB(at - 1.5, top, at + 1.5, top + height),
      white,
    );
    // A knob at each end of the line to show it can be taken hold of.
    for (final double y in <double>[top, top + height]) {
      canvas.drawCircle(Offset(at, y), 5.5 + 1.5 * lit, white);
      canvas.drawCircle(Offset(at, y), 3.5 + lit, Paint()..color = editRed);
    }
  }

  @override
  bool shouldRepaint(EditPainter old) =>
      old.plan != plan ||
      old.view != view ||
      old.selected != selected ||
      old.selectedCut != selectedCut ||
      old.selecting != selecting;
}
