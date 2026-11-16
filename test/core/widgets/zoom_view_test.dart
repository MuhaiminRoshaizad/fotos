import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/zoom_view.dart';

void main() {
  /// A ZoomView inside a scale gesture of its own, as a video sits inside
  /// the viewer's swipe-down-to-close handler. Returns how many updates the
  /// outer gesture got.
  Future<List<int>> wrapped(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<int> outer = <int>[0];
    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          onScaleUpdate: (_) => outer[0]++,
          child: const ZoomView(
            child: ColoredBox(
              color: Colors.teal,
              child: SizedBox.expand(child: Text('video')),
            ),
          ),
        ),
      ),
    );
    return outer;
  }

  Matrix4 transform(WidgetTester tester) =>
      tester.state<ZoomViewState>(find.byType(ZoomView)).transform;

  Future<void> doubleTap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
  }

  testWidgets('at normal size a one-finger swipe goes to the gesture around '
      'it, such as swipe-down-to-close', (WidgetTester tester) async {
    final List<int> outer = await wrapped(tester);
    await tester.drag(find.text('video'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(outer[0], greaterThan(0));
    expect(transform(tester).getMaxScaleOnAxis(), 1);
  });

  testWidgets('two fingers zoom in', (WidgetTester tester) async {
    await wrapped(tester);
    final TestGesture a = await tester.startGesture(
      const Offset(180, 400),
      pointer: 21,
    );
    final TestGesture b = await tester.startGesture(
      const Offset(220, 400),
      pointer: 22,
    );
    for (int i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(transform(tester).getMaxScaleOnAxis(), greaterThan(2));
  });

  testWidgets('a double-tap zooms in where it lands; zoomed in, one finger '
      'pans and the gesture around gets nothing', (WidgetTester tester) async {
    final List<int> outer = await wrapped(tester);
    const Offset spot = Offset(100, 200);
    await doubleTap(tester, spot);
    final Matrix4 m = transform(tester);
    expect(m.getMaxScaleOnAxis(), closeTo(ZoomView.tapScale, 0.01));
    final Offset mapped = MatrixUtils.transformPoint(m, spot);
    expect(mapped.dx, closeTo(spot.dx, 0.5));
    expect(mapped.dy, closeTo(spot.dy, 0.5));

    outer[0] = 0;
    final double before = transform(tester).getTranslation().y;
    // In small steps, as a finger moves.
    final TestGesture g = await tester.startGesture(const Offset(200, 300));
    for (int i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, -15));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(transform(tester).getTranslation().y, lessThan(before - 50));
    expect(outer[0], 0);

    await doubleTap(tester, spot);
    expect(transform(tester).getMaxScaleOnAxis(), closeTo(1, 0.01));
  });

  /// A pinch as a hand makes it: the second finger lands a moment after the
  /// first, which has drifted a little, and then [still] stays put while
  /// the other finger moves by [step] ten times.
  Future<void> pinch(
    WidgetTester tester, {
    required Offset still,
    required Offset moving,
    required Offset step,
  }) async {
    final TestGesture a = await tester.startGesture(still, pointer: 31);
    await a.moveBy(step / 2);
    await tester.pump(const Duration(milliseconds: 40));
    final TestGesture b = await tester.startGesture(moving, pointer: 32);
    for (int i = 0; i < 10; i++) {
      await b.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a pinch with one finger held still zooms instead of turning '
      'the page', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final PageController c = PageController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PageView(
          controller: c,
          children: <Widget>[
            for (int i = 0; i < 2; i++)
              ZoomView(child: SizedBox.expand(child: Text('page $i'))),
          ],
        ),
      ),
    );
    await pinch(
      tester,
      still: const Offset(150, 400),
      moving: const Offset(200, 400),
      step: const Offset(12, 0),
    );
    expect(c.page, 0);
    expect(transform(tester).getMaxScaleOnAxis(), greaterThan(1.5));
  });

  testWidgets('a pinch along a scrolling list zooms instead of scrolling', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ScrollController s = ScrollController();
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ZoomView(
          child: ListView.builder(
            controller: s,
            itemCount: 50,
            itemExtent: 300,
            itemBuilder: (_, int i) => Text('panel $i'),
          ),
        ),
      ),
    );
    await pinch(
      tester,
      still: const Offset(200, 500),
      moving: const Offset(200, 400),
      step: const Offset(0, -12),
    );
    expect(s.offset, 0);
    expect(transform(tester).getMaxScaleOnAxis(), greaterThan(1.5));
  });

  testWidgets('a scroll already going keeps going when a second finger '
      'lands', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ScrollController s = ScrollController();
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ZoomView(
          child: ListView.builder(
            controller: s,
            itemCount: 50,
            itemExtent: 300,
            itemBuilder: (_, int i) => Text('panel $i'),
          ),
        ),
      ),
    );
    final TestGesture a = await tester.startGesture(const Offset(200, 600));
    for (int i = 0; i < 5; i++) {
      await a.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final TestGesture b = await tester.startGesture(
      const Offset(300, 600),
      pointer: 41,
    );
    await b.moveBy(const Offset(0, -30));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(s.offset, greaterThan(50));
    expect(transform(tester).getMaxScaleOnAxis(), 1);
  });

  testWidgets('at normal size a swipe turns the page of a page view', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final PageController c = PageController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PageView(
          controller: c,
          children: <Widget>[
            for (int i = 0; i < 2; i++)
              ZoomView(child: SizedBox.expand(child: Text('page $i'))),
          ],
        ),
      ),
    );
    await tester.fling(find.text('page 0'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(c.page, 1);
  });

  testWidgets('zoomed into a strip, a diagonal drag scrolls the strip and '
      'pans across it at once', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ScrollController s = ScrollController();
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ZoomView(
          scrollAxis: Axis.vertical,
          child: ListView.builder(
            controller: s,
            itemCount: 50,
            itemExtent: 300,
            itemBuilder: (_, int i) => Text('panel $i'),
          ),
        ),
      ),
    );
    await doubleTap(tester, const Offset(200, 400));
    expect(transform(tester).getMaxScaleOnAxis(), greaterThan(2));
    final double x = transform(tester).getTranslation().x;

    final TestGesture g = await tester.startGesture(const Offset(200, 500));
    for (int i = 0; i < 10; i++) {
      await g.moveBy(const Offset(12, -12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(s.offset, greaterThan(20), reason: 'the strip scrolls');
    expect(
      transform(tester).getTranslation().x,
      greaterThan(x + 60),
      reason: 'and the zoom pans sideways',
    );

    // Straight sideways, nothing scrolls: the finger only pans.
    final double offset = s.offset;
    final double x2 = transform(tester).getTranslation().x;
    final TestGesture h = await tester.startGesture(const Offset(200, 500));
    for (int i = 0; i < 8; i++) {
      await h.moveBy(const Offset(-15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await h.up();
    await tester.pumpAndSettle();
    expect(s.offset, offset);
    expect(transform(tester).getTranslation().x, lessThan(x2 - 60));
  });
}
