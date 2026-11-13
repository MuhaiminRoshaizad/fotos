import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/album_id.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/files/presentation/file_actions.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('a folder renamed in Files keeps its album pinned, and its '
      "subfolders' albums too", () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestWidgetsFlutterBinding.ensureInitialized();
    const MethodChannel channel = MethodChannel('my.minned.fotos/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => 0);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final Directory storage = await Directory.systemTemp.createTemp('fotos');
    addTearDown(() => storage.delete(recursive: true));
    final String from = p.join(storage.path, 'Pictures', 'Clips');
    final String to = p.join(storage.path, 'Pictures', 'Game clips');
    await Directory(p.join(to, 'Racing')).create(recursive: true);

    final ProviderContainer c = ProviderContainer(
      overrides: [
        storageRootProvider.overrideWith((Ref ref) async => storage.path),
      ],
    );
    addTearDown(c.dispose);
    await c.read(storageRootProvider.future);
    await c.read(albumPrefsProvider.future);
    final AlbumPrefsNotifier prefs = c.read(albumPrefsProvider.notifier);
    await prefs.togglePin(albumIdOf(p.join(from, 'Racing')));
    await prefs.togglePin(albumIdOf(from));
    await prefs.togglePin('other');

    await followRenamed(c, from, to);

    expect(c.read(albumPrefsProvider).value!.pinned, <String>[
      'other',
      albumIdOf(to),
      albumIdOf(p.join(to, 'Racing')),
    ]);
  });
}
