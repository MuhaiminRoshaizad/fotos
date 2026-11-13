import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/core/selection/selection.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/albums/data/galleries.dart';
import 'package:fotos/features/albums/presentation/album_tiles.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_media_repository.dart';

Album _album(String id) => Album(
  id: id,
  name: 'Comic $id',
  count: 3,
  path: AssetPathEntity(id: id, name: 'Comic $id'),
);

class _NoEmpty extends EmptyAlbumsNotifier {
  @override
  Future<List<String>> build() async => const <String>[];
}

void main() {
  late ProviderContainer container;

  Future<void> openAlbums(WidgetTester tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          albumsProvider.overrideWith(
            (Ref ref) async => <Album>[
              for (int i = 1; i <= 6; i++) _album('$i'),
            ],
          ),
          emptyAlbumsProvider.overrideWith(_NoEmpty.new),
          albumPrefsProvider.overrideWith(AlbumPrefsNotifier.new),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Albums').last);
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(AlbumTile).first),
    );
  }

  Set<String> selected() => container.read(selectionProvider).ids;

  testWidgets('selected albums go into a new gallery in one go', (
    WidgetTester tester,
  ) async {
    await openAlbums(tester);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Select albums'), findsOneWidget);

    await tester.tap(find.text('Comic 1'));
    await tester.pump();
    await tester.tap(find.text('Comic 2'));
    await tester.pumpAndSettle();
    expect(selected(), <String>{'1', '2'});
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('To gallery').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New gallery'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Read');
    await tester.tap(find.text('Make gallery'));
    await tester.pumpAndSettle();

    final List<Gallery> galleries = container.read(galleriesProvider).value!;
    expect(galleries.single.name, 'Read');
    expect(galleries.single.albumIds, <String>['1', '2']);
    expect(container.read(selectionProvider).active, isFalse);
    expect(find.byType(GalleryTile), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('holding a tile while selecting and dragging selects every '
      'tile passed', (WidgetTester tester) async {
    await openAlbums(tester);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    final TestGesture g = await tester.startGesture(
      tester.getCenter(find.text('Comic 1')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    for (int i = 0; i < 10; i++) {
      await g.moveBy(
        (tester.getCenter(find.text('Comic 4')) -
                tester.getCenter(find.text('Comic 1'))) /
            10,
      );
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(selected(), <String>{'1', '2', '3', '4'});
  });

  testWidgets("a tile's hold menu offers Select, which starts with it ticked", (
    WidgetTester tester,
  ) async {
    await openAlbums(tester);
    await tester.longPress(find.text('Comic 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    expect(container.read(selectionProvider).active, isTrue);
    expect(selected(), <String>{'3'});
  });
}
