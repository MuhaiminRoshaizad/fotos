import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/core/media/media_tile.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
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
      name: 'Pets',
      count: items.length,
      path: AssetPathEntity(id: 'a', name: 'Pets'),
    ),
  ];
}

AssetEntity _item(String id, DateTime date, {bool fav = false}) => AssetEntity(
  id: id,
  typeInt: 1,
  width: 1,
  height: 1,
  isFavorite: fav,
  createDateSecond: date.millisecondsSinceEpoch ~/ 1000,
);

/// Newest first, as the library hands them over: two in November, two in
/// October, one favourite in each month.
final List<AssetEntity> _pets = <AssetEntity>[
  _item('n1', DateTime(2026, 11, 9)),
  _item('n2', DateTime(2026, 11, 2), fav: true),
  _item('o1', DateTime(2026, 10, 20), fav: true),
  _item('o2', DateTime(2026, 10, 3)),
];

Future<ProviderContainer> _open(WidgetTester tester) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.fluttercandies/photo_manager'),
        (MethodCall call) async => call.method == 'getThumb' ? _pixel : null,
      );
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ProviderContainer providers = ProviderContainer(
    overrides: [mediaRepositoryProvider.overrideWithValue(_Library(_pets))],
    retry: (_, _) => null,
  );
  addTearDown(providers.dispose);
  final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: providers,
      child: MaterialApp(navigatorKey: nav, home: const SizedBox()),
    ),
  );
  nav.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => const AlbumScreen(albumId: 'a')),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  return providers;
}

List<String> _tiles(WidgetTester tester) => tester
    .widgetList<MediaTile>(find.byType(MediaTile))
    .map((MediaTile t) => t.asset.id)
    .toList();

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('switched on in the Sort sheet, an album gathers its favourites '
      'under their own heading above the dates', (WidgetTester tester) async {
    final ProviderContainer providers = await _open(tester);
    expect(find.text('Favourites'), findsNothing);
    expect(_tiles(tester), <String>['n1', 'n2', 'o1', 'o2']);

    await tester.tap(find.byTooltip('Album options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort'));
    await tester.pumpAndSettle();
    expect(
      find.text('Favourites sit at the top, like a pinned album.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Favourites first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(_tiles(tester), <String>['n2', 'o1', 'n1', 'o2']);
    expect(find.text('Favourites'), findsOneWidget);
    expect(_top(tester, 'Favourites'), lessThan(_top(tester, 'November 2026')));
    expect(find.text('October 2026'), findsOneWidget);
    // Saved for this album only.
    final AlbumPrefs prefs = providers.read(albumPrefsProvider).value!;
    expect(prefs.sortFor('a').favouritesFirst, isTrue);
    expect(prefs.defaultSort.favouritesFirst, isFalse);
  });

  testWidgets('switched back off, the favourites return to their dates', (
    WidgetTester tester,
  ) async {
    final ProviderContainer providers = await _open(tester);
    await providers
        .read(albumPrefsProvider.notifier)
        .setSort(
          'a',
          const AlbumSort(AlbumSortBy.taken, favouritesFirst: true),
        );
    await tester.pumpAndSettle();
    expect(_tiles(tester), <String>['n2', 'o1', 'n1', 'o2']);

    await providers
        .read(albumPrefsProvider.notifier)
        .setSort('a', AlbumSort.standard);
    await tester.pumpAndSettle();
    expect(_tiles(tester), <String>['n1', 'n2', 'o1', 'o2']);
    expect(find.text('Favourites'), findsNothing);
  });
}
