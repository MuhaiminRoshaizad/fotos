import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/zoom_view.dart';

void main() {
  Future<PageController> pages(WidgetTester tester) async {
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
              ZoomView(
                child: ColoredBox(
                  color: Colors.primaries[i],
                  child: SizedBox.expand(child: Text('page $i')),
                ),
              ),
          ],
        ),
      ),
    );
    return c;
  }

  Matrix4 matrix(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
      .transformationController!
      .value;

  Future<void> doubleTap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
  }

  testWidgets('a double-tap zooms in where it lands, and another zooms out', (
    WidgetTester tester,
  ) async {
    await pages(tester);
    const Offset spot = Offset(100, 200);
    await doubleTap(tester, spot);
    final Matrix4 m = matrix(tester);
    expect(m.getMaxScaleOnAxis(), closeTo(ZoomView.tapScale, 0.01));
    // The tapped spot stays under the finger.
    final Offset mapped = MatrixUtils.transformPoint(m, spot);
    expect(mapped.dx, closeTo(spot.dx, 0.5));
    expect(mapped.dy, closeTo(spot.dy, 0.5));

    await doubleTap(tester, spot);
    expect(matrix(tester).getMaxScaleOnAxis(), closeTo(1, 0.01));
  });

  testWidgets('at normal size a swipe turns the page; zoomed in it pans', (
    WidgetTester tester,
  ) async {
    final PageController c = await pages(tester);
    await tester.drag(find.text('page 0'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(c.page, 1);

    c.jumpToPage(0);
    await tester.pumpAndSettle();
    await doubleTap(tester, const Offset(200, 400));
    await tester.drag(find.text('page 0'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(c.page, 0);
  });
}
