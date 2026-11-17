import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/grouping.dart';
import 'package:fotos/core/media/media_grid.dart';
import 'package:fotos/core/media/media_tile.dart';
import 'package:fotos/features/viewer/presentation/viewer_screen.dart';
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

  final List<AssetEntity> photos = <AssetEntity>[
    for (int i = 0; i < 200; i++)
      AssetEntity(id: '$i', typeInt: 1, width: 400, height: 300),
  ];

  /// The tile of [id] fully inside the 400 x 800 screen.
  bool onScreen(WidgetTester tester, String id) {
    final Finder tile = find.byKey(ValueKey<String>(id));
    if (tile.evaluate().isEmpty) return false;
    final Rect r = tester.getRect(tile);
    return r.top >= 0 && r.bottom <= 800;
  }

  testWidgets('closing the viewer after swiping on lands on the last photo', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: MediaGrid(
                items: photos,
                level: GridLevel.all,
                heroPrefix: 'photos',
                grouped: false,
                // As the app opens it: see-through, so the grid stays laid
                // out behind the viewer.
                onOpen: (int index, RevealItem reveal) =>
                    Navigator.of(context).push(
                      PageRouteBuilder<void>(
                        opaque: false,
                        pageBuilder: (_, _, _) => ViewerScreen(
                          args: ViewerArgs(
                            items: photos,
                            index: index,
                            heroPrefix: 'photos',
                            onShow: reveal,
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final ScrollPosition grid = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;

    await tester.tap(find.byType(MediaTile).at(2));
    await tester.pumpAndSettle();
    expect(grid.pixels, 0, reason: 'the tapped tile was already in view');

    // Forty photos on: far below the first screen of the grid.
    for (int i = 0; i < 40; i++) {
      await tester.fling(
        find.byType(ViewerScreen),
        const Offset(-300, 0),
        1500,
      );
      await tester.pumpAndSettle();
    }
    expect(find.bySemanticsLabel('Item 43 of 200'), findsOneWidget);

    Navigator.of(tester.element(find.byType(ViewerScreen))).pop();
    await tester.pumpAndSettle();
    expect(grid.pixels, greaterThan(0));
    expect(onScreen(tester, '42'), isTrue);
    expect(onScreen(tester, '2'), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
