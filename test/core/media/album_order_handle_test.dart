import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/grouping.dart';
import 'package:fotos/core/media/media_grid.dart';
import 'package:fotos/core/widgets/scroll_handle.dart';
import 'package:photo_manager/photo_manager.dart';

/// A 1x1 grey PNG.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
);

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fluttercandies/photo_manager'),
          (MethodCall call) async => call.method == 'getThumb' ? _pixel : null,
        );
  });

  final List<AssetEntity> pages = <AssetEntity>[
    for (int i = 0; i < 400; i++)
      AssetEntity(id: '$i', typeInt: 1, width: 1000, height: 1400),
  ];
  final Finder handle = find.byIcon(CupertinoIcons.chevron_up_chevron_down);

  Future<ScrollPosition> open(
    WidgetTester tester, {
    HandleLabel Function(AssetEntity, int, int)? orderLabel,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MediaGrid(
              items: pages,
              level: GridLevel.all,
              heroPrefix: 'album',
              onOpen: (_) {},
              grouped: false,
              orderLabel: orderLabel,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final ScrollPosition pos = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    pos.jumpTo(10);
    await tester.pump();
    return pos;
  }

  testWidgets('an album sorted by name gets a handle that says how far in', (
    WidgetTester tester,
  ) async {
    final ScrollPosition pos = await open(
      tester,
      orderLabel: (AssetEntity e, int i, int n) =>
          HandleLabel('${i + 1}', secondary: 'of $n'),
    );
    expect(handle, findsOneWidget);
    final TestGesture g = await tester.startGesture(tester.getCenter(handle));
    for (int i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, 15));
      await tester.pump();
    }
    await tester.pump();
    expect(pos.pixels, greaterThan(2000));
    expect(find.text('of 400'), findsOneWidget);
    await g.up();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('without an order label an ungrouped grid has no handle', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(handle, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
