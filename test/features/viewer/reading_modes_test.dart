import 'dart:convert';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/read_mode.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/viewer/presentation/strip_viewer.dart';
import 'package:fotos/features/viewer/presentation/viewer_screen.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A 1x1 grey PNG.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
);

/// Comic pages: 1000 wide, 1400 tall.
AssetEntity _page(String id) =>
    AssetEntity(id: id, typeInt: 1, width: 1000, height: 1400);

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fluttercandies/photo_manager'),
          (MethodCall call) async => call.method == 'getThumb' ? _pixel : null,
        );
  });

  Future<void> open(WidgetTester tester, ReadMode mode) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ViewerScreen(
            args: ViewerArgs(
              items: <AssetEntity>[_page('a'), _page('b'), _page('c')],
              index: 1,
              heroPrefix: 'album-comic',
              readMode: mode,
              title: 'Iron Orchard',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  double? page(WidgetTester tester) => tester
      .widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView),
      )
      .controller
      .page;

  /// Lets a tap through (it waits out a double tap) and the page turn run.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('in Pages mode a tap on the right turns forward and on the '
      'left turns back', (WidgetTester tester) async {
    await open(tester, ReadMode.pages);
    expect(page(tester), 1);
    await tester.tapAt(const Offset(370, 400));
    await settle(tester);
    expect(page(tester), 2);
    await tester.tapAt(const Offset(30, 400));
    await settle(tester);
    await tester.tapAt(const Offset(30, 400));
    await settle(tester);
    expect(page(tester), 0);
    await finish(tester);
  });

  testWidgets('read as photos, a tap at the edge only shows or hides the '
      'controls', (WidgetTester tester) async {
    await open(tester, ReadMode.photos);
    await tester.tapAt(const Offset(370, 400));
    await settle(tester);
    expect(page(tester), 1);
    await finish(tester);
  });

  testWidgets('read as a strip, every page sits at its true height and it '
      'opens at the chosen page', (WidgetTester tester) async {
    await open(tester, ReadMode.strip);
    expect(find.byType(StripViewer), findsOneWidget);
    // 400 wide pages of 1000x1400 are 560 tall; page 2 starts at 560.
    final ScrollPosition pos = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(pos.pixels, 560);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('Iron Orchard'), findsOneWidget);
    await finish(tester);
  });

  test('an album remembers how it is read, through a rename too', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(albumPrefsProvider.future);
    final AlbumPrefsNotifier prefs = c.read(albumPrefsProvider.notifier);
    await prefs.setReading('comic', ReadMode.strip);
    expect(
      c.read(albumPrefsProvider).value!.readingFor('comic'),
      ReadMode.strip,
    );
    expect(
      c.read(albumPrefsProvider).value!.readingFor('camera'),
      ReadMode.photos,
    );
    await prefs.rekey('comic', 'comic-renamed');
    expect(
      c.read(albumPrefsProvider).value!.readingFor('comic-renamed'),
      ReadMode.strip,
    );
  });
}
