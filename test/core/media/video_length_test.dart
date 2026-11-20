import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_tile.dart';
import 'package:fotos/core/media/video_length.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  Future<void> tile(WidgetTester tester, AssetEntity asset) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            // As read from the file of a fragmented MP4.
            videoLengthProvider.overrideWith(
              (Ref ref, AssetEntity a) async => const Duration(seconds: 14),
            ),
          ],
          child: MaterialApp(
            home: SizedBox.square(
              dimension: 120,
              child: MediaTile(asset: asset, heroTag: 'v'),
            ),
          ),
        ),
      );

  testWidgets('a video Android lists as 0:00 shows the length read from its '
      'file', (WidgetTester tester) async {
    await tile(
      tester,
      AssetEntity(id: 'v', typeInt: 2, width: 1, height: 1, duration: 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('0:14'), findsOneWidget);
    expect(find.text('0:00'), findsNothing);
  });

  testWidgets("a video with Android's length shows it, without reading the "
      'file', (WidgetTester tester) async {
    await tile(
      tester,
      AssetEntity(id: 'v', typeInt: 2, width: 1, height: 1, duration: 42),
    );
    expect(find.text('0:42'), findsOneWidget);
  });
}
