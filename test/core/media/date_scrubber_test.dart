import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/date_scrubber.dart';

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
                child: DateScrubber(controller: c, labelAt: (double o) => '$o'),
              ),
            ],
          ),
        ),
      ),
    );
    // Scrolling a little shows the handle.
    c.jumpTo(1);
    await tester.pump();

    final Finder handle = find.byIcon(Icons.unfold_more);
    final TestGesture g = await tester.startGesture(tester.getCenter(handle));
    for (int i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await g.up();
    await tester.pump();

    // Track = 600 - 48 handle; 100 px of finger travel scrolls 100/552 of the
    // extent (plus the 1 px start), not double that.
    final double max = c.position.maxScrollExtent;
    expect(c.offset, closeTo(1 + 100 / 552 * max, max * 0.02));
  });
}
