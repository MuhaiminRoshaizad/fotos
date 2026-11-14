import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/video_editor/domain/cut_plan.dart';
import 'package:fotos/features/video_editor/domain/timeline_view.dart';
import 'package:fotos/features/video_editor/presentation/cut_timeline.dart';
import 'package:fotos/features/video_editor/presentation/timeline_frames.dart';

/// The timeline with a plan and a playhead it changes, as the editor holds
/// them.
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
  final TimelineFrames frames = TimelineFrames(
    (List<int> times) async => <Uint8List?>[for (final int _ in times) null],
  );

  @override
  void dispose() {
    frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: CutTimeline(
          plan: plan,
          frames: frames,
          position: position,
          playing: false,
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
  // 400 wide. Zoomed out, 100 s spans half of it less the end handle's
  // room, and with the playhead at 0 the video starts in the middle.
  const double width = 400;
  const double middle = width / 2;
  const double outMs = 100000 / (width / 2 - TimelineView.endRoom);

  Future<_HarnessState> open(WidgetTester tester, CutPlan plan) async {
    tester.view.physicalSize = const Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_Harness(plan));
    return tester.state<_HarnessState>(find.byType(_Harness));
  }

  CutTimelineState timeline(WidgetTester tester) =>
      tester.state<CutTimelineState>(find.byType(CutTimeline));

  Offset at(WidgetTester tester, double x) =>
      Offset(x, tester.getCenter(find.byType(CutTimeline)).dy);

  /// Two fingers either side of the middle, spreading by [by] each.
  Future<void> spread(WidgetTester tester, double by) async {
    final TestGesture a = await tester.startGesture(
      at(tester, middle - 20),
      pointer: 71,
    );
    final TestGesture b = await tester.startGesture(
      at(tester, middle + 20),
      pointer: 72,
    );
    for (int i = 0; i < 10; i++) {
      await a.moveBy(Offset(-by / 10, 0));
      await b.moveBy(Offset(by / 10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a handle taken off-centre moves with the finger without '
      'jumping, the strip holds still, and both stay put when let go', (
    WidgetTester tester,
  ) async {
    final _HarnessState s = await open(tester, CutPlan.whole(100000));
    // Taken 6 points to the right of the start handle.
    final TestGesture g = await tester.startGesture(at(tester, middle + 6));
    for (int i = 0; i < 3; i++) {
      await g.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    // 30 points moved, 30 points' worth of time: no jump to centre the
    // handle under the finger, which would add the 6 it was taken off by.
    expect(s.plan.start, closeTo(30 * outMs, outMs));
    expect(timeline(tester).view.centre, 0);

    for (int i = 0; i < 7; i++) {
      await g.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    final int dropped = s.plan.start;
    expect(dropped, closeTo(100 * outMs, outMs));
    await g.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(s.plan.start, dropped);
    expect(timeline(tester).view.centre, 0);
    // The picture goes back to the frame under the playhead.
    expect(s.position, 0);
  });

  testWidgets('dragging the strip scrolls the video under the playhead, and '
      'it stays where it is let go', (WidgetTester tester) async {
    final _HarnessState s = await open(tester, CutPlan.whole(100000));
    // Well clear of the handles at 200 and 372.
    await tester.dragFrom(at(tester, 300), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(s.plan.changed, isFalse);
    expect(s.position, closeTo(100 * outMs, outMs));
    expect(timeline(tester).view.centre, closeTo(100 * outMs, outMs));
    await tester.pump(const Duration(seconds: 2));
    expect(timeline(tester).view.centre, closeTo(100 * outMs, outMs));
  });

  testWidgets('two fingers zoom in, no further than ten seconds across', (
    WidgetTester tester,
  ) async {
    await open(tester, CutPlan.whole(3600000));
    final double out = timeline(tester).view.msPerPoint;
    expect(out, 3600000 / (middle - TimelineView.endRoom));
    await spread(tester, 60);
    expect(timeline(tester).view.msPerPoint, lessThan(out / 2));
    await spread(tester, 150);
    await spread(tester, 150);
    await spread(tester, 150);
    expect(timeline(tester).view.msPerPoint, 10000 / width);
  });

  testWidgets('zoomed in on an hour, the intro can be cut to the tenth', (
    WidgetTester tester,
  ) async {
    final _HarnessState s = await open(tester, CutPlan.whole(3600000));
    for (int i = 0; i < 4; i++) {
      await spread(tester, 150);
    }
    // 25 ms a point: 30 s is 1200 points away, past the screen's edge.
    // Hold the start handle at the right edge to scroll along.
    final TestGesture g = await tester.startGesture(at(tester, middle));
    for (int i = 0; i < 20; i++) {
      await g.moveBy(const Offset(9.5, 0));
      await tester.pump();
    }
    // Until 30 s is on screen: the strip shows 5 s either side.
    for (int i = 0; i < 300 && timeline(tester).view.centre < 27000; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(timeline(tester).view.centre, greaterThanOrEqualTo(27000));
    // Then back off the edge and place it by hand.
    await g.moveTo(at(tester, middle + 100));
    await tester.pump();
    final double centre = timeline(tester).view.centre;
    final int target = 30000;
    await g.moveTo(at(tester, middle + (target - centre) / 25));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(s.plan.start, closeTo(target, 25));
  });

  testWidgets('a tap on the strip glides the playhead there, not a jump', (
    WidgetTester tester,
  ) async {
    final _HarnessState s = await open(tester, CutPlan.whole(100000));
    await tester.tapAt(at(tester, 300));
    // The glide starts on the frame after the tap.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(s.position, closeTo(100 * outMs, outMs));
    // On its way, not there yet.
    expect(
      timeline(tester).view.centre,
      allOf(greaterThan(0), lessThan(s.position)),
    );
    await tester.pumpAndSettle();
    expect(timeline(tester).view.centre, s.position);
  });

  testWidgets('a handle reaching its neighbour ticks once as it stops', (
    WidgetTester tester,
  ) async {
    final List<Object?> haptics = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    CutPlan plan = CutPlan.whole(100000);
    (plan, _) = plan.addCut(50000)!; // 45 s to 55 s
    await open(tester, plan);
    final TestGesture g = await tester.startGesture(
      at(tester, middle + 45000 / outMs),
    );
    for (int i = 0; i < 10; i++) {
      await g.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(haptics, <Object?>['HapticFeedbackType.selectionClick']);
  });

  testWidgets('a handle dragged past its neighbour stops beside it', (
    WidgetTester tester,
  ) async {
    CutPlan plan = CutPlan.whole(100000);
    (plan, _) = plan.addCut(50000)!; // 45 s to 55 s
    final _HarnessState s = await open(tester, plan);
    // The cut's start handle, dragged right over its end.
    final TestGesture g = await tester.startGesture(
      at(tester, middle + 45000 / outMs),
    );
    for (int i = 0; i < 10; i++) {
      await g.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(s.plan.cuts.single.start, 55000 - CutPlan.minPart);
    expect(s.plan.cuts.single.end, 55000);
  });
}
