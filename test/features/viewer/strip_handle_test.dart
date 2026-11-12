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
}
