import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/features/viewer/presentation/viewer_screen.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_media_repository.dart';

/// A 1x1 grey PNG.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
);

void main() {
  Future<void> open(WidgetTester tester, AssetEntity item) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fluttercandies/photo_manager'),
          (MethodCall call) async => call.method == 'getThumb' ? _pixel : null,
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
        child: MaterialApp(
          home: ViewerScreen(
            args: ViewerArgs(
              items: <AssetEntity>[item],
              index: 0,
              heroPrefix: 'grid',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  // A video's bar is checked on a phone: photo_manager hands out files
  // only on Android, and the video page asks for one as it opens.
  testWidgets('a photo has no Edit: only videos can be cut', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      AssetEntity(id: 'p', typeInt: 1, width: 400, height: 300),
    );
    expect(find.bySemanticsLabel('Edit'), findsNothing);
    expect(find.bySemanticsLabel('Share'), findsOneWidget);
    await close(tester);
  });
}
