import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/zoom_view.dart';
import 'package:fotos/features/viewer/presentation/strip_viewer.dart';

/// A 1x1 grey PNG.
final MemoryImage _pixel = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
  ),
);

void main() {
  testWidgets('a strip zooms on a double-tap and still scrolls with one '
      'finger at normal size', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StripViewer(
          title: 'Iron Orchard',
          pages: <StripPage>[
            for (int i = 0; i < 20; i++)
              StripPage(aspect: 1000 / 1400, image: (_) => _pixel),
          ],
          index: 0,
        ),
      ),
    );
    final ScrollPosition pos = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(pos.pixels, greaterThan(200));

    const Offset spot = Offset(200, 400);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(spot);
    await tester.pumpAndSettle();
    final Matrix4 m = tester
        .state<ZoomViewState>(find.byType(ZoomView))
        .transform;
    expect(m.getMaxScaleOnAxis(), closeTo(ZoomView.tapScale, 0.01));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
