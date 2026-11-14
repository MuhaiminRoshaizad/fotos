import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/video_editor/domain/timeline_view.dart';

void main() {
  const double width = 400;

  test('zoomed out, the whole video spans half the strip from the middle', () {
    final TimelineView v = TimelineView.fit(3600000, width);
    expect(v.xOf(0, width), 200);
    // Room left for the end handle's grip.
    expect(v.xOf(3600000, width), 400 - TimelineView.endRoom);
    expect(v.msAt(200 + (200 - TimelineView.endRoom) / 2, width), 1800000);
  });

  test('zoom stays between the whole video and ten seconds across', () {
    final TimelineView v = TimelineView.fit(3600000, width);
    expect(v.zoomed(0.001, width).msPerPoint, 10000 / width);
    expect(
      v.zoomed(1e9, width).msPerPoint,
      3600000 / (width / 2 - TimelineView.endRoom),
    );
    // A video shorter than ten seconds never zooms past fitting.
    final TimelineView short = TimelineView.fit(4000, width);
    expect(short.zoomed(0.001, width).msPerPoint, short.msPerPoint);
  });

  test('the playhead stays on the video', () {
    final TimelineView v = TimelineView.fit(60000, width);
    expect(v.at(-5).centre, 0);
    expect(v.at(90000).centre, 60000);
  });

  test('frames sit a step apart, at least a tile wide and under two', () {
    final TimelineView v = TimelineView.fit(3600000, width).zoomed(25, width);
    expect(v.tileStep(40), 1000);
    for (double mpp = 25; mpp < 30000; mpp *= 1.3) {
      final TimelineView z = TimelineView.fit(
        3600000,
        width,
      ).zoomed(mpp, width);
      expect(z.tileStep(40) / z.msPerPoint, inInclusiveRange(40, 80));
    }
  });

  test('zooming in splits every tile in two, so no frame moves', () {
    final TimelineView whole = TimelineView.fit(3600000, width);
    int coarser = whole.tileStep(40);
    for (double mpp = whole.msPerPoint; mpp > 25; mpp /= 1.1) {
      final int step = whole.zoomed(mpp, width).tileStep(40);
      // Every tile start at the coarser zoom is a tile start here too.
      expect(coarser % step, 0);
      coarser = step;
    }
  });
}
