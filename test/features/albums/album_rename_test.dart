import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/albums/presentation/album_sheets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Album _album(String name) => Album(
  id: name,
  name: name,
  count: 1,
  path: AssetPathEntity(id: name, name: name),
);

void main() {
  test('a renamed album keeps its place beside the old folder', () {
    expect(renamedFolder('Pictures/Trip/', 'Holiday'), 'Pictures/Holiday/');
    expect(
      renamedFolder('DCIM/Clips/CVR clips/', 'VR clips'),
      'DCIM/Clips/VR clips/',
    );
    expect(renamedFolder('Download/', 'Saved'), 'Saved/');
  });

  test('Camera and Screenshots offer no Rename', () {
    expect(
      albumOptionsFor(_album('Camera')),
      isNot(contains(AlbumOption.rename)),
    );
    expect(
      albumOptionsFor(_album('Screenshots')),
      isNot(contains(AlbumOption.rename)),
    );
    expect(albumOptionsFor(_album('CVR clips')), contains(AlbumOption.rename));
  });

  test('pin, cover and sort follow the album to its new id', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(albumPrefsProvider.future);
    final AlbumPrefsNotifier prefs = c.read(albumPrefsProvider.notifier);
    await prefs.togglePin('other');
    await prefs.togglePin('old');
    await prefs.setCover('old', 'photo-7');
    final AlbumSort byName = AlbumSort(AlbumSortBy.values.last, reversed: true);
    await prefs.setSort('old', byName);

    await prefs.rekey(<String, String>{'old': 'new'});

    final AlbumPrefs p = c.read(albumPrefsProvider).value!;
    // Keeps its place in the pinned order, under its new id.
    expect(p.pinned, <String>['new', 'other']);
    expect(p.covers, <String, String>{'new': 'photo-7'});
    expect(p.sortFor('new').by, byName.by);
    expect(p.sortFor('new').reversed, isTrue);
    expect(p.sorts.containsKey('old'), isFalse);
  });

  test('renaming back onto an id still pinned keeps one pin, and the moved '
      "album's cover", () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(albumPrefsProvider.future);
    final AlbumPrefsNotifier prefs = c.read(albumPrefsProvider.notifier);
    // "clips" was renamed while the rename lost pins, so its id stayed.
    await prefs.togglePin('clips');
    await prefs.setCover('clips', 'stale');
    await prefs.togglePin('clipssss');
    await prefs.setCover('clipssss', 'photo-3');

    await prefs.rekey(<String, String>{'clipssss': 'clips'});

    final AlbumPrefs p = c.read(albumPrefsProvider).value!;
    expect(p.pinned, <String>['clips']);
    expect(p.covers, <String, String>{'clips': 'photo-3'});
  });

  test('a pinned list saved with an id twice loads with it once', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          'albums.prefs': '{"pinned":["a","b","a"]}',
        });
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    expect((await c.read(albumPrefsProvider.future)).pinned, <String>[
      'a',
      'b',
    ]);
  });
}
