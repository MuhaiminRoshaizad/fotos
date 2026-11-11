import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/viewer/presentation/viewer_screen.dart';
import 'package:photo_manager/photo_manager.dart';

/// A 1x1 grey PNG.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
);

AssetEntity _photo(String id) =>
    AssetEntity(id: id, typeInt: 1, width: 400, height: 300);

void main() {
  setUp(() {
    // No photo library in a test: every thumbnail is one grey pixel and
    // every other lookup comes back empty.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fluttercandies/photo_manager'),
          (MethodCall call) async => call.method == 'getThumb' ? _pixel : null,
        );
  });

  testWidgets('opened on one photo, the viewer takes in the library when it '
      'lands and stays on that photo', (WidgetTester tester) async {
    final Completer<List<AssetEntity>> library = Completer<List<AssetEntity>>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ViewerScreen(
            args: ViewerArgs(
              items: <AssetEntity>[_photo('b')],
              index: 0,
              heroPrefix: 'intent',
              library: library.future,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Item 1 of 1'), findsOneWidget);

    library.complete(<AssetEntity>[_photo('a'), _photo('b'), _photo('c')]);
    await tester.pump();
    await tester.pump();
    // The same photo, now second of three, with neighbours to swipe to.
    expect(find.bySemanticsLabel('Item 2 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Item 1 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Item 3 of 3'), findsOneWidget);

    // Let the image loads that were started finish before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
