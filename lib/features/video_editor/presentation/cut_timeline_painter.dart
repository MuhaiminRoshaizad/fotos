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
              _tile(i, step, view.xOf(i * step, width)),
        ],
      ),
    );
  }

  Widget _tile(int i, int step, double x) {
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
      child: ClipRect(child: image),
    );
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
    required this.top,
    required this.height,
  });

  final CutPlan plan;
  final TimelineView view;
  final Handle? selected;
  final int? selectedCut;
  final double top;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    double x(int ms) => view.xOf(ms, w);
    final double bottom = top + height;
    Rect band(int from, int to) => Rect.fromLTRB(x(from), top, x(to), bottom);

    // What is left out: dimmed outside the ends, red where cut.
    final Paint dim = Paint()..color = const Color(0xB3000000);
    canvas.drawRect(band(0, plan.start), dim);
    canvas.drawRect(band(plan.end, plan.duration), dim);
    for (int i = 0; i < plan.cuts.length; i++) {
      final Span c = plan.cuts[i];
      final Rect r = band(c.start, c.end);
      canvas.drawRect(r, dim);
      canvas.drawRect(
        r,
        Paint()
          ..color = editRed.withValues(alpha: i == selectedCut ? 0.55 : 0.35),
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
    _endHandle(canvas, l - 12, l, selected == const Handle.start());
    _endHandle(canvas, r, r + 12, selected == const Handle.end());

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

  void _endHandle(Canvas canvas, double left, double right, bool on) {
    final RRect grip = RRect.fromRectAndRadius(
      Rect.fromLTRB(left, top - 3, right, top + height + 3),
      const Radius.circular(4),
    );
    canvas.drawRRect(grip, Paint()..color = on ? Colors.white : editYellow);
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
    final bool on = selected == h;
    final Paint white = Paint()
      ..color = on ? Colors.white : const Color(0xE6FFFFFF);
    canvas.drawRect(
      Rect.fromLTRB(at - 1.5, top, at + 1.5, top + height),
      white,
    );
    // A knob at each end of the line to show it can be taken hold of.
    for (final double y in <double>[top, top + height]) {
      canvas.drawCircle(Offset(at, y), on ? 7 : 5.5, white);
      canvas.drawCircle(
        Offset(at, y),
        on ? 4.5 : 3.5,
        Paint()..color = editRed,
      );
    }
  }

  @override
  bool shouldRepaint(EditPainter old) =>
      old.plan != plan ||
      old.view != view ||
      old.selected != selected ||
      old.selectedCut != selectedCut;
}
