import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/video/strip_tiles.dart';
import 'package:skeletonizer/skeletonizer.dart';

// A 1x1 transparent PNG.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _host(Widget child, {bool still = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: still),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(width: 48, height: 48, child: child),
  ),
);

void main() {
  testWidgets('a tile is empty until its picture comes, then shows it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const FrameTile(frame: null)));
    expect(find.byType(Image), findsNothing);

    await tester.pumpWidget(_host(FrameTile(frame: _png)));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the strip shimmers only while a picture is still to come', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const StripLoading(loading: true)));
    Skeletonizer s = tester.widget(_skeleton);
    expect(s.enabled, isTrue);
    expect(s.effect, isA<ShimmerEffect>());

    await tester.pumpWidget(_host(const StripLoading(loading: false)));
    s = tester.widget(_skeleton);
    expect(s.enabled, isFalse);
  });

  testWidgets('with animations off, the loading strip holds still', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const StripLoading(loading: true), still: true),
    );
    final Skeletonizer s = tester.widget(_skeleton);
    expect(s.effect, isA<SolidColorEffect>());
  });
}

// Skeletonizer is abstract, so match it by kind rather than exact type.
final Finder _skeleton = find.byWidgetPredicate(
  (Widget w) => w is Skeletonizer,
);
