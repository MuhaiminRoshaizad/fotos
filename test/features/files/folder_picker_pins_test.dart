import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/folder_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('the Files tab\'s pins are shortcuts in the folder picker', (
    WidgetTester tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final Directory root = Directory.systemTemp.createTempSync('picker');
    addTearDown(() => root.deleteSync(recursive: true));
    String dir(String rel) =>
        (Directory(p.join(root.path, rel))..createSync(recursive: true)).path;
    final String download = dir('Download');
    final String album = dir(p.join('Comic', 'Album'));
    final String moving = dir('Moving');

    final ProviderContainer container = ProviderContainer(
      overrides: [
        // Every folder reads as empty: the pins are what is under test.
        folderProvider.overrideWith(
          (Ref ref, String path) async => const <FileEntry>[],
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(filesTabPinsProvider.future);
    final FilesTabPinsNotifier pins = container.read(
      filesTabPinsProvider.notifier,
    );
    await pins.toggle(album);
    await pins.toggle(moving);

    String? picked;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              onPressed: () async => picked = await pickFolder(
                context,
                ref,
                start: download,
                root: root.path,
                action: 'Move here',
                exclude: <String>{moving},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);
    // The folder being moved can't be its own destination.
    expect(find.text('Moving'), findsNothing);

    await tester.tap(find.text('Album'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move here'));
    await tester.pumpAndSettle();
    expect(picked, album);
  });
}
