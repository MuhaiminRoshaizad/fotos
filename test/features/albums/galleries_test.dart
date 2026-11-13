import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/albums/data/galleries.dart';
import 'package:fotos/features/albums/presentation/album_tiles.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_media_repository.dart';

Album _album(String id, String name) => Album(
  id: id,
  name: name,
  count: 3,
  path: AssetPathEntity(id: id, name: name),
);

class _NoEmpty extends EmptyAlbumsNotifier {
  @override
  Future<List<String>> build() async => const <String>[];
}

class _NoPrefs extends AlbumPrefsNotifier {
  @override
  Future<AlbumPrefs> build() async => const AlbumPrefs();
}

/// "Clips" holds the two game albums, newest-first by default but sorted
/// A to Z here.
class _OneGallery extends GalleriesNotifier {
  @override
  Future<List<Gallery>> build() async => const <Gallery>[
    Gallery(
      id: '${galleryIdPrefix}1',
      name: 'Clips',
      albumIds: <String>['2', '1'],
      order: AlbumsOrder(AlbumsOrderBy.name),
    ),
  ];
}

void main() {
  group('the gallery store', () {
    late ProviderContainer c;
    late GalleriesNotifier galleries;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      c = ProviderContainer();
      await c.read(galleriesProvider.future);
      galleries = c.read(galleriesProvider.notifier);
    });
    tearDown(() => c.dispose());

    List<Gallery> now() => c.read(galleriesProvider).value!;

    test('an album sits in one gallery at most', () async {
      final String clips = await galleries.create('Clips', <String>['a', 'b']);
      final String chats = await galleries.create('Chats', <String>['b', 'c']);
      expect(clips, startsWith(galleryIdPrefix));
      expect(galleryOf(now(), 'a')!.id, clips);
      // Making Chats took b out of Clips.
      expect(galleryOf(now(), 'b')!.id, chats);

      await galleries.add(clips, <String>['c']);
      expect(now().firstWhere((Gallery g) => g.id == clips).albumIds, <String>[
        'a',
        'c',
      ]);
      expect(now().firstWhere((Gallery g) => g.id == chats).albumIds, <String>[
        'b',
      ]);

      await galleries.remove('a');
      expect(galleryOf(now(), 'a'), isNull);
    });

    test('a renamed album stays in its gallery, and ungrouping keeps the '
        'others', () async {
      final String clips = await galleries.create('Clips', <String>['old']);
      await galleries.create('Chats', <String>['x']);
      await galleries.rekey(<String, String>{'old': 'new'});
      expect(galleryOf(now(), 'new')!.id, clips);

      await galleries.rename(clips, 'Game clips');
      await galleries.setOrder(
        clips,
        const AlbumsOrder(AlbumsOrderBy.name, reversed: true),
      );
      await galleries.delete(clips);
      expect(now().map((Gallery g) => g.name), <String>['Chats']);
    });

    test('galleries are still there the next time the app starts', () async {
      await galleries.create('Clips', <String>['a']);
      final ProviderContainer next = ProviderContainer();
      addTearDown(next.dispose);
      final List<Gallery> again = await next.read(galleriesProvider.future);
      expect(again.single.name, 'Clips');
      expect(again.single.albumIds, <String>['a']);
    });
  });

  testWidgets('a gallery shows on Albums in place of its albums, and opens '
      'to them in its own order', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          albumsProvider.overrideWith(
            (Ref ref) async => <Album>[
              _album('1', 'gaming clips'),
              _album('2', 'CVR clips'),
              _album('3', 'Download'),
            ],
          ),
          emptyAlbumsProvider.overrideWith(_NoEmpty.new),
          albumPrefsProvider.overrideWith(_NoPrefs.new),
          galleriesProvider.overrideWith(_OneGallery.new),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Albums').last);
    await tester.pumpAndSettle();

    expect(find.byType(GalleryTile), findsOneWidget);
    expect(find.text('2 albums'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    // Its albums are inside it, not beside it.
    expect(find.text('CVR clips'), findsNothing);

    await tester.tap(find.byType(GalleryTile));
    await tester.pumpAndSettle();
    final List<String> inside = <String>[
      for (final AlbumTile t in tester.widgetList<AlbumTile>(
        find.byType(AlbumTile),
      ))
        t.album.name,
    ];
    expect(inside, <String>['CVR clips', 'gaming clips']);
    expect(find.text('Download'), findsNothing);
  });
}
