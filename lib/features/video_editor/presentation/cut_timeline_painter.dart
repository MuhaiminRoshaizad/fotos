import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../domain/cut_plan.dart';

// The editor is always dark, as the viewer is. iOS's own system yellow and
// red, the colours its trim and destructive controls use.
const Color editYellow = Color(0xFFFFD60A);
const Color editRed = Color(0xFFFF3B30);

/// The video's frames along the timeline; a still-loading strip is plain.
class TimelineFrames extends StatelessWidget {
  const TimelineFrames({super.key, required this.frames});

  final List<Uint8List?>? frames;

  @override
  Widget build(BuildContext context) {
    final List<Uint8List?> all = frames ?? const <Uint8List?>[];
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: ColoredBox(
        color: const Color(0xFF2C2C2E),
        child: Row(
          children: <Widget>[
            for (final Uint8List? f in all.isEmpty ? <Uint8List?>[null] : all)
              Expanded(
                child: f == null
                    ? const SizedBox.expand()
                    : Image.memory(
                        f,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        gaplessPlayback: true,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Everything drawn over the frames: what is left out, the yellow frame
/// and grips round what is kept, the cut handles and the playhead.
class EditPainter extends CustomPainter {
  EditPainter({
    required this.plan,
    required this.position,
    required this.selected,
    required this.selectedCut,
    required this.inset,
    required this.top,
    required this.height,
  });

  final CutPlan plan;
  final int position;
  final Handle? selected;
  final int? selectedCut;
  final double inset;
  final double top;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width - 2 * inset;
    double x(int ms) => inset + ms / plan.duration * w;
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

    // The playhead, over everything.
    final double p = x(position.clamp(0, plan.duration));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(p - 1.5, top - 6, p + 1.5, bottom + 6),
        const Radius.circular(1.5),
      ),
      Paint()
        ..color = Colors.white
        ..maskFilter = null,
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
      old.position != position ||
      old.selected != selected ||
      old.selectedCut != selectedCut;
}
