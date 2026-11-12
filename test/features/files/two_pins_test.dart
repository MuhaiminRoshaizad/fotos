import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fotos_pins');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'pinning to the top and adding to the Files tab are kept apart',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(topPinsProvider.future);
      await c.read(filesTabPinsProvider.future);

      await c
          .read(topPinsProvider.notifier)
          .toggle('/root/Comic/Album/Moonlit');
      await c.read(filesTabPinsProvider.notifier).toggle('/root/Comic/Album');

      expect(c.read(topPinsProvider).value, <String>[
        '/root/Comic/Album/Moonlit',
      ]);
      expect(c.read(filesTabPinsProvider).value, <String>['/root/Comic/Album']);
    },
  );

  test('a file pinned before the split becomes pinned to the top; folders '
      'stay on the Files tab', () async {
    final String comic = p.join(root.path, 'Moonlit Harbor.cbz');
    await File(comic).writeAsString('x');
    final String folder = (await Directory(
      p.join(root.path, 'Comic'),
    ).create()).path;
    final InMemorySharedPreferencesAsync store =
        InMemorySharedPreferencesAsync.empty();
    await store.setStringList('files.pinned', <String>[
      comic,
      folder,
    ], const SharedPreferencesOptions());
    SharedPreferencesAsyncPlatform.instance = store;

    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(topPinsProvider.future), <String>[comic]);
    // The Files tab shows folders only, so the file there no longer shows.
    expect(await c.read(filesTabPinsProvider.future), contains(folder));
  });
}
