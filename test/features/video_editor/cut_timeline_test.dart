import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/video_editor/domain/cut_plan.dart';
import 'package:fotos/features/video_editor/presentation/cut_timeline.dart';

/// The timeline with a plan it changes, as the editor holds one.
class _Harness extends StatefulWidget {
  const _Harness(this.start);

  final CutPlan start;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late CutPlan plan = widget.start;
  int position = 0;
  Handle? selected;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: CutTimeline(
          plan: plan,
          frames: null,
          position: position,
          selected: selected,
          selectedCut: null,
          onMove: (Handle h, int ms) => setState(() {
            plan = plan.move(h, ms);
            selected = h;
          }),
          onScrub: (int ms) => setState(() => position = ms),
          onDragStart: () {},
          onDragEnd: () {},
          onSelect: (Handle? h) => setState(() => selected = h),
          onSelectCut: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  // 400 wide, less 24 either side: 352 px for 100 s.
  const double width = 400;
  const double inset = CutTimeline.inset;
  const double perSecond = (width - 2 * inset) / 100;

  Future<_HarnessState> open(WidgetTester tester, CutPlan plan) async {
    tester.view.physicalSize = const Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_Harness(plan));
    return tester.state<_HarnessState>(find.byType(_Harness));
  }

  Offset at(WidgetTester tester, double x) =>
      Offset(x, tester.getCenter(find.byType(CutTimeline)).dy);

  testWidgets('a handle taken off-centre moves with the finger without '
      'jumping, and stays where it is let go', (WidgetTester tester) async {
    final _HarnessState s = await open(tester, CutPlan.whole(100000));
    // Taken 6 px to the right of the start handle.
    final TestGesture g = await tester.startGesture(at(tester, inset + 6));
    for (int i = 0; i < 3; i++) {
      await g.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    // 30 px moved, 30 px worth of time: no jump to centre the handle
    // under the finger, which would add the 6 px it was taken off by.
    expect(s.plan.start, closeTo(30 * 1000 / perSecond, 150));

    for (int i = 0; i < 7; i++) {
      await g.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    final int dropped = s.plan.start;
    expect(dropped, closeTo(100 * 1000 / perSecond, 150));
    await g.up();
    await tester.pumpAndSettle();
    expect(s.plan.start, dropped);
    await tester.pump(const Duration(seconds: 2));
    expect(s.plan.start, dropped);
  });

  testWidgets('a handle dragged past its neighbour stops beside it', (
    WidgetTester tester,
  ) async {
    CutPlan plan = CutPlan.whole(100000);
    (plan, _) = plan.addCut(50000)!; // 45 s to 55 s
    final _HarnessState s = await open(tester, plan);
    // The cut's start handle, dragged far right over its end.
    final TestGesture g = await tester.startGesture(
      at(tester, inset + 45 * perSecond),
    );
    for (int i = 0; i < 20; i++) {
      await g.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(s.plan.cuts.single.start, 55000 - CutPlan.minPart);
    expect(s.plan.cuts.single.end, 55000);
  });

  testWidgets('a drag away from the handles moves the playhead only', (
    WidgetTester tester,
  ) async {
    final _HarnessState s = await open(tester, CutPlan.whole(100000));
    await tester.dragFrom(
      at(tester, inset + 30 * perSecond),
      const Offset(70, 0),
    );
    await tester.pumpAndSettle();
    expect(s.plan.changed, isFalse);
    expect(s.position, closeTo(50000, 700));
  });
}
