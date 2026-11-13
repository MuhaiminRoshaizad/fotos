import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/albums/presentation/album_sheets.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../support/fake_media_repository.dart';

Album _album(String id, String name) => Album(
  id: id,
  name: name,
  count: 2,
  path: AssetPathEntity(id: id, name: name),
);

/// A library whose album gets a new id once its items move, as Android
/// gives a renamed folder.
class _Library extends FakeMediaRepository {
  List<Album> list = <Album>[_album('old', 'Trip')];

  @override
  Future<List<Album>> albums() async => list;

  // On the phone this asks Android, so frames, and the tile's rebuild, get
  // in between.
  @override
  Future<String?> folderOf(Album album) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return super.folderOf(album);
  }

  @override
  Future<bool> moveTo(List<AssetEntity> items, String relativePath) async {
    list = <Album>[_album('new', 'Holiday')];
    folders['new'] = relativePath;
    return super.moveTo(items, relativePath);
  }
}

/// Lists a tile per album, as the Albums tab does, so the renamed album's
/// tile, and its ref, goes away with the old id.
class _Albums extends ConsumerWidget {
  const _Albums();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Album> albums = ref.watch(albumsProvider).value ?? <Album>[];
    return Column(
      children: <Widget>[
        for (final Album a in albums) _Tile(a, key: ValueKey<String>(a.id)),
      ],
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile(this.album, {super.key});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    onPressed: () => renameAlbum(context, ref, album),
    child: Text('Rename ${album.name}'),
  );
}

void main() {
  testWidgets('renaming from a tile that goes away keeps the pin, says '
      'so and clears the emptied folder', (WidgetTester tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('my.minned.fotos/native'),
          (MethodCall call) async => 0,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('my.minned.fotos/native'),
            null,
          ),
    );
    final _Library library = _Library()..folders['old'] = 'Pictures/Trip/';
    // Android leaves the moved album's folder behind, empty.
    final Directory storage = Directory.systemTemp.createTempSync('fotos');
    addTearDown(() => storage.deleteSync(recursive: true));
    final Directory old = Directory(p.join(storage.path, 'Pictures', 'Trip'))
      ..createSync(recursive: true);
    final ProviderContainer c = ProviderContainer(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(library),
        storageRootProvider.overrideWith((Ref ref) async => storage.path),
      ],
    );
    addTearDown(c.dispose);
    await c.read(albumPrefsProvider.future);
    await c.read(albumPrefsProvider.notifier).togglePin('old');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: _Albums())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename Trip'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Holiday');
    await tester.tap(find.text('Rename'));
    // The progress bar holds its result on screen for a moment.
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Clearing the old folder is real disk work, outside the test's clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(library.moves, <String>['Pictures/Holiday/']);
    expect(c.read(albumsProvider).value!.single.id, 'new');
    expect(find.text('Rename Trip'), findsNothing);
    expect(find.text('Rename Holiday'), findsOneWidget);
    expect(c.read(albumPrefsProvider).value!.pinned, <String>['new']);
    expect(find.text('Renamed to Holiday'), findsOneWidget);
    expect(old.existsSync(), isFalse);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
