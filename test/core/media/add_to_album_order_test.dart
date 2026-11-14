import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/add_to_album.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_media_repository.dart';

Album _album(String id, String name) => Album(
  id: id,
  name: name,
  count: 1,
  path: AssetPathEntity(id: id, name: name),
);

/// Albums in the jumbled order Android hands them over in.
class _Library extends FakeMediaRepository {
  @override
  Future<List<Album>> albums() async => <Album>[
    _album('z', 'Zoo'),
    _album('m', 'Movies'),
    _album('a', 'Art'),
  ];
}

void main() {
  testWidgets('the sheet lists pinned albums first, then the tab\'s order', (
    WidgetTester tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final ProviderContainer container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(_Library())],
    );
    addTearDown(container.dispose);
    await container.read(albumPrefsProvider.future);
    final AlbumPrefsNotifier prefs = container.read(
      albumPrefsProvider.notifier,
    );
    await prefs.togglePin('m');
    await prefs.setOrder(const AlbumsOrder(AlbumsOrderBy.name));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              onPressed: () => addToAlbum(context, ref, <AssetEntity>[]),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Pinned'), lessThan(y('Movies')));
    expect(y('Movies'), lessThan(y('Albums')));
    expect(y('Albums'), lessThan(y('Art')));
    expect(y('Art'), lessThan(y('Zoo')));
  });

  testWidgets('with nothing pinned the sheet has no headings', (
    WidgetTester tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaRepositoryProvider.overrideWithValue(_Library())],
        child: MaterialApp(
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              onPressed: () => addToAlbum(context, ref, <AssetEntity>[]),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Pinned'), findsNothing);
    expect(find.text('Albums'), findsNothing);
    expect(find.text('Zoo'), findsOneWidget);
  });
}
