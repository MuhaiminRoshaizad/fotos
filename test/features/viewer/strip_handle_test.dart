import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/viewer/presentation/strip_viewer.dart';

/// A 1x1 grey PNG.
final MemoryImage _pixel = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
  ),
);

void main() {
  testWidgets('dragging the handle through a long strip names the page it '
      'lands on', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StripViewer(
          title: 'Iron Orchard',
          // 40 pages, each 400 x 560 on this screen.
          pages: <StripPage>[
            for (int i = 0; i < 40; i++)
              StripPage(aspect: 1000 / 1400, image: (_) => _pixel),
          ],
          index: 0,
        ),
      ),
    );
    final ScrollPosition pos = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    // The handle shows once the strip scrolls.
    pos.jumpTo(10);
    await tester.pump();
    final Finder handle = find.byIcon(CupertinoIcons.chevron_up_chevron_down);
    expect(handle, findsOneWidget);

    final TestGesture g = await tester.startGesture(tester.getCenter(handle));
    for (int i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, 15));
      await tester.pump();
    }
    await tester.pump();
    // The label names the page under the middle of the screen.
    final int page = ((pos.pixels + 400) / 560).floor() + 1;
    expect(pos.pixels, greaterThan(5000));
    expect(find.text('Page $page'), findsOneWidget);
    expect(find.text('of 40'), findsOneWidget);
    await g.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the handle moves steadily down a strip of uneven pages', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Short and very tall pages mixed, as strip chapters are: 200 px and
    // 2000 px high at this width, in an uneven pattern.
    final List<double> heights = <double>[
      for (int i = 0; i < 60; i++) i % 7 == 0 || i % 11 == 0 ? 2000 : 200,
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: StripViewer(
          title: 'Iron Orchard',
          pages: <StripPage>[
            for (final double h in heights)
              StripPage(aspect: 400 / h, image: (_) => _pixel),
          ],
          index: 0,
        ),
      ),
    );
    final ScrollPosition pos = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    final double length = heights.reduce((double a, double b) => a + b);
    final Finder handle = find.byIcon(CupertinoIcons.chevron_up_chevron_down);
    double last = -1;
    for (double y = 0; y < length - 800; y += 450) {
      pos.jumpTo(y);
      await tester.pump();
      // The strip's true length, whichever pages are on screen.
      expect(pos.maxScrollExtent, length - 800, reason: 'at $y');
      final double top = tester.getTopLeft(handle).dy;
      expect(top, greaterThanOrEqualTo(last), reason: 'at $y');
      last = top;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
