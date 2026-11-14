import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/video_editor/domain/cut_plan.dart';

void main() {
  const int min = CutPlan.minPart;

  test('a new plan keeps the whole video and has not changed', () {
    final CutPlan p = CutPlan.whole(60000);
    expect(p.kept, const <Span>[Span(0, 60000)]);
    expect(p.keptLength, 60000);
    expect(p.changed, isFalse);
  });

  test('cutting an intro keeps the rest', () {
    final CutPlan p = CutPlan.whole(60000).move(const Handle.start(), 8000);
    expect(p.kept, const <Span>[Span(8000, 60000)]);
    expect(p.keptLength, 52000);
    expect(p.changed, isTrue);
  });

  test('two parts cut from the middle leave three kept, in order', () {
    CutPlan p = CutPlan.whole(100000);
    (p, _) = p.addCut(30000)!;
    (p, _) = p.addCut(70000)!;
    expect(p.cuts, const <Span>[Span(25000, 35000), Span(65000, 75000)]);
    expect(p.kept, const <Span>[
      Span(0, 25000),
      Span(35000, 65000),
      Span(75000, 100000),
    ]);
    expect(p.keptLength, 80000);
  });

  test('a cut added before another goes in its place in the order', () {
    CutPlan p = CutPlan.whole(100000);
    (p, _) = p.addCut(70000)!;
    final (CutPlan q, int index) = p.addCut(20000)!;
    expect(index, 0);
    expect(q.cuts.first.start, lessThan(q.cuts.last.start));
  });

  test('a handle stops at its neighbour instead of crossing it', () {
    CutPlan p = CutPlan.whole(100000);
    (p, _) = p.addCut(50000)!; // cut 45000..55000
    // Dragged far past both sides.
    expect(
      p.move(const Handle.cutStart(0), 99000).cuts.single.start,
      55000 - min,
    );
    expect(p.move(const Handle.cutEnd(0), 0).cuts.single.end, 45000 + min);
    expect(p.move(const Handle.start(), 99000).start, 45000 - min);
    expect(p.move(const Handle.end(), 0).end, 55000 + min);
    // And never off the video.
    expect(p.move(const Handle.start(), -5000).start, 0);
    expect(p.move(const Handle.end(), 500000).end, 100000);
  });

  test('a handle lands exactly where it is put when there is room', () {
    final CutPlan p = CutPlan.whole(100000).move(const Handle.end(), 81234);
    expect(p.end, 81234);
    expect(p.at(const Handle.end()), 81234);
  });

  test('no cut is added where it would leave nothing kept beside it', () {
    final CutPlan p = CutPlan.whole(1200);
    expect(p.addCut(600), isNull);
  });

  test('a cut fits inside the kept part it is added in', () {
    CutPlan p = CutPlan.whole(100000).move(const Handle.start(), 20000);
    // Near the start handle: pushed right so something stays kept before it.
    (p, _) = p.addCut(20100)!;
    expect(p.cuts.single.start, 20000 + min);
  });

  test('a cut can be made as wide as the strip shows, around the playhead', () {
    final (CutPlan p, _) = CutPlan.whole(3600000).addCut(30000, width: 3000)!;
    expect(p.cuts.single, const Span(28500, 31500));
  });

  test('a removed cut is kept again', () {
    CutPlan p = CutPlan.whole(100000);
    (p, _) = p.addCut(50000)!;
    p = p.removeCut(0);
    expect(p.kept, const <Span>[Span(0, 100000)]);
  });

  test('playback skips what is cut and stops after the last kept part', () {
    CutPlan p = CutPlan.whole(100000).move(const Handle.start(), 5000);
    (p, _) = p.addCut(50000)!; // 45000..55000
    expect(p.keptFrom(0), 5000);
    expect(p.keptFrom(20000), 20000);
    expect(p.keptFrom(47000), 55000);
    expect(p.keptFrom(100000), isNull);
    expect(p.cutAt(47000), 0);
    expect(p.cutAt(20000), isNull);
  });
}
