import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/features/albums/presentation/album_screen.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_media_repository.dart';

/// A 1x1 grey PNG.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
);

/// An album of 300 photos whose reloads take a moment, as on the phone.
class _Library extends FakeMediaRepository {
  _Library()
    : super(
        items: <AssetEntity>[
          for (int i = 0; i < 300; i++)
            AssetEntity(id: '$i', typeInt: 1, width: 1, height: 1),
        ],
      );

  @override
  Future<List<Album>> albums() async => <Album>[
    Album(
      id: 'a',
      name: 'Trip',
      count: items.length,
      path: AssetPathEntity(id: 'a', name: 'Trip'),
    ),
  ];

  @override
  Future<List<AssetEntity>> albumItems(Album album) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return items;
  }
}

/// Opens the album, scrolls well down, applies [change] as a delete or a
/// move would, and returns where the grid ends up.
Future<double> _placeAfter(
  WidgetTester tester,
  void Function(_Library repo, ProviderContainer providers) change,
) async {
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
  final _Library repo = _Library();
  final ProviderContainer providers = ProviderContainer(
    overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
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
  // Pushed, as from the Albums tab, so it has a back button.
  nav.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => const AlbumScreen(albumId: 'a')),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(3000);
  await tester.pump();

  change(repo, providers);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  return tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;
}

void main() {
  testWidgets('an album keeps its place when something in it is deleted', (
    WidgetTester tester,
  ) async {
    // As MediaActions.trash refreshes after the item leaves.
    final double at = await _placeAfter(tester, (
      _Library repo,
      ProviderContainer providers,
    ) {
      repo.items = repo.items.skip(1).toList();
      providers
        ..invalidate(libraryProvider)
        ..invalidate(albumsProvider)
        ..invalidate(favouritesProvider);
    });
    expect(at, closeTo(3000, 200));
  });

  testWidgets('an album keeps its place when something moves out of it', (
    WidgetTester tester,
  ) async {
    // As addToAlbum refreshes after a move to another album.
    final double at = await _placeAfter(tester, (
      _Library repo,
      ProviderContainer providers,
    ) {
      repo.items = repo.items.skip(1).toList();
      providers
        ..invalidate(libraryProvider)
        ..invalidate(albumsProvider);
    });
    expect(at, closeTo(3000, 200));
  });
}
