import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/scroll_handle.dart';

void main() {
  testWidgets('the handle follows the finger 1:1', (WidgetTester tester) async {
    final ScrollController c = ScrollController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 600,
          child: Stack(
            children: <Widget>[
              ListView(
                controller: c,
                children: <Widget>[const SizedBox(height: 600 * 20)],
              ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: ScrollHandle(
                  controller: c,
                  labelAt: (double o) => HandleLabel('$o'),
                  semanticLabel: 'Scroll',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Scrolling a little shows the handle.
    c.jumpTo(1);
    await tester.pump();

    final Finder handle = find.byIcon(CupertinoIcons.chevron_up_chevron_down);
    final TestGesture g = await tester.startGesture(tester.getCenter(handle));
    for (int i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await g.up();
    await tester.pump();

    // Track = 600 - 72 touch area; 100 px of finger travel scrolls 100/528
    // of the extent (plus the 1 px start), not double that.
    final double max = c.position.maxScrollExtent;
    expect(c.offset, closeTo(1 + 100 / 528 * max, max * 0.01));
  });

  group('grip, label and marks', () {
    const MethodChannel channel = MethodChannel('my.minned.fotos/native');
    final List<List<Object?>> exclusions = <List<Object?>>[];
    late ScrollController c;

    setUp(() {
      exclusions.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'setGestureExclusion') {
              exclusions.add(
                (call.arguments as Map<Object?, Object?>)['rects']!
                    as List<Object?>,
              );
            }
            return null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    Future<void> pumpHandle(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: <Widget>[
              ListView(
                controller: c,
                children: <Widget>[const SizedBox(height: 600 * 20)],
              ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: ScrollHandle(
                  controller: c,
                  semanticLabel: 'Scroll',
                  labelAt: (double o) => HandleLabel(
                    o < 6000 ? 'March' : 'July',
                    secondary: '2026',
                    mark: o < 6000 ? '2026' : '2025',
                  ),
                  marks: () => const <HandleMark>[
                    HandleMark(0, '2026'),
                    HandleMark(10, 'too close'),
                    HandleMark(6000, '2025'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      c.jumpTo(1);
      await tester.pump();
    }

    Size thumbSize(WidgetTester tester) => tester.getSize(
      find
          .ancestor(
            of: find.byIcon(CupertinoIcons.chevron_up_chevron_down),
            matching: find.byType(Container),
          )
          .first,
    );

    testWidgets('a grab beside the handle still catches it, and it grows '
        'while held', (WidgetTester tester) async {
      await pumpHandle(tester);
      expect(thumbSize(tester), const Size(32, 48));
      final Offset handle = tester.getCenter(
        find.byIcon(CupertinoIcons.chevron_up_chevron_down),
      );
      // 20 px left of the handle's centre, outside the handle drawn.
      final TestGesture g = await tester.startGesture(
        handle - const Offset(26, 0),
      );
      await tester.pump();
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(thumbSize(tester).width, closeTo(46, 1));
      expect(thumbSize(tester).height, closeTo(64, 1));
      await g.moveBy(const Offset(0, 300));
      await tester.pump();
      await tester.pump();
      expect(c.offset, greaterThan(6000));
      // The bubble names the spot; marks line the track, the crowded one
      // dropped.
      expect(find.text('July'), findsOneWidget);
      expect(find.text('2025'), findsOneWidget);
      expect(find.text('too close'), findsNothing);
      await g.up();
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(thumbSize(tester).width, closeTo(32, 0.5));
      expect(thumbSize(tester).height, closeTo(48, 0.5));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets("Android's back swipe is switched off over the handle while "
        'it shows, and back on once it hides', (WidgetTester tester) async {
      await pumpHandle(tester);
      await tester.pump();
      final List<Object?> on = exclusions.last;
      expect(on, hasLength(1));
      final List<int> r = (on.single! as List<Object?>).cast<int>();
      // The 56 x 72 touch area against the right edge.
      expect(r[2], 400);
      // Rounded outward to whole pixels.
      expect(r[2] - r[0], closeTo(56, 1));
      expect(r[3] - r[1], closeTo(72, 1));
      await tester.pump(const Duration(seconds: 2));
      expect(exclusions.last, isEmpty);
    });
  });
}
