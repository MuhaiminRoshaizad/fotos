import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/core/media/media_tile.dart';
import 'package:fotos/features/albums/presentation/album_screen.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_media_repository.dart';

/// A 1x1 grey PNG.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
);

class _Library extends FakeMediaRepository {
  _Library(List<AssetEntity> items) : super(items: items);

  @override
  Future<List<Album>> albums() async => <Album>[
    Album(
      id: 'a',
      name: 'Trip',
      count: items.length,
      path: AssetPathEntity(id: 'a', name: 'Trip'),
    ),
  ];
}

/// Four photos and two videos.
final List<AssetEntity> _mixed = <AssetEntity>[
  fakeAsset('p1'),
  fakeAsset('v1', video: true),
  fakeAsset('p2'),
  fakeAsset('p3'),
  fakeAsset('v2', video: true),
  fakeAsset('p4'),
];

Future<void> _open(WidgetTester tester, List<AssetEntity> items) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.fluttercandies/photo_manager'),
        (MethodCall call) async => call.method == 'getThumb' ? _pixel : null,
      );
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [mediaRepositoryProvider.overrideWithValue(_Library(items))],
      child: MaterialApp(navigatorKey: nav, home: const SizedBox()),
    ),
  );
  nav.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => const AlbumScreen(albumId: 'a')),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

final Finder _switch = find.byType(
  CupertinoSlidingSegmentedControl<MediaShown>,
);

int _tiles(WidgetTester tester) => find.byType(MediaTile).evaluate().length;

void main() {
  testWidgets('a mixed album narrows to videos and back, counting them', (
    WidgetTester tester,
  ) async {
    await _open(tester, _mixed);
    expect(_switch, findsOneWidget);
    expect(find.text('6 items'), findsOneWidget);
    expect(_tiles(tester), 6);

    await tester.tap(
      find.descendant(of: _switch, matching: find.text('Videos')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // The old tiles fade out before the new ones arrive.
    expect(_tiles(tester), 6);
    await tester.pumpAndSettle();
    expect(_tiles(tester), 2);
    expect(find.text('2 videos'), findsOneWidget);
    final List<String> ids = tester
        .widgetList<MediaTile>(find.byType(MediaTile))
        .map((MediaTile t) => t.asset.id)
        .toList();
    expect(ids, unorderedEquals(<String>['v1', 'v2']));

    await tester.tap(
      find.descendant(of: _switch, matching: find.text('Photos')),
    );
    await tester.pumpAndSettle();
    expect(_tiles(tester), 4);
    expect(find.text('4 photos'), findsOneWidget);

    await tester.tap(find.descendant(of: _switch, matching: find.text('All')));
    await tester.pumpAndSettle();
    expect(_tiles(tester), 6);
    expect(find.text('6 items'), findsOneWidget);
  });

  testWidgets(
    'the bar carries what the album is narrowed to, for when it collapses',
    (WidgetTester tester) async {
      await _open(tester, _mixed);
      expect(find.text('Videos only'), findsNothing);
      await tester.tap(
        find.descendant(of: _switch, matching: find.text('Videos')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Videos only'), findsOneWidget);
    },
  );

  testWidgets('Select all takes only what is showing, and the switch is still '
      'while selecting', (WidgetTester tester) async {
    await _open(tester, _mixed);
    await tester.tap(
      find.descendant(of: _switch, matching: find.text('Videos')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(
      find.descendant(of: _switch, matching: find.text('All')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(_tiles(tester), 2);
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('an album of one kind has no switch', (
    WidgetTester tester,
  ) async {
    await _open(tester, <AssetEntity>[fakeAsset('p1'), fakeAsset('p2')]);
    expect(_switch, findsNothing);
    expect(find.text('2 items'), findsOneWidget);
  });
}
