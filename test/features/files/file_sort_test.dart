import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

FileEntry _e(String name, {bool folder = false, int size = 0, int day = 1}) =>
    FileEntry(
      path: '/root/Comic/Album/$name',
      name: name,
      kind: kindOf(name, isDirectory: folder),
      size: size,
      modified: DateTime(2026, 11, day),
    );

void main() {
  final List<FileEntry> album = <FileEntry>[
    _e('Paper Tigers 12', folder: true, day: 3),
    _e('Iron Orchard 2', folder: true, day: 9),
    _e('Iron Orchard 10', folder: true, day: 1),
    _e('notes.txt', size: 10, day: 5),
    _e('Glass Lantern.cbz', size: 900, day: 2),
  ];
  List<String> names(FileSort s) =>
      s.apply(album).map((FileEntry e) => e.name).toList();

  test('folders stay ahead of files, each part in the chosen order', () {
    expect(names(FileSort.standard), <String>[
      'Iron Orchard 2',
      'Iron Orchard 10',
      'Paper Tigers 12',
      'Glass Lantern.cbz',
      'notes.txt',
    ]);
    // The newest extracted comic first: what "recently added" means here.
    expect(names(const FileSort(FileSortBy.modified)), <String>[
      'Iron Orchard 2',
      'Paper Tigers 12',
      'Iron Orchard 10',
      'notes.txt',
      'Glass Lantern.cbz',
    ]);
    expect(names(const FileSort(FileSortBy.size)).skip(3), <String>[
      'Glass Lantern.cbz',
      'notes.txt',
    ]);
    expect(names(const FileSort(FileSortBy.type)).skip(3), <String>[
      'Glass Lantern.cbz',
      'notes.txt',
    ]);
    expect(
      names(const FileSort(FileSortBy.name, reversed: true)).first,
      'Paper Tigers 12',
    );
  });

  test('Use for all folders makes a default; a folder can keep its own, '
      'and keeps it through a rename', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(fileSortsProvider.future);
    final FileSortsNotifier sorts = c.read(fileSortsProvider.notifier);

    await sorts.set('/root/Comic/Album', const FileSort(FileSortBy.modified));
    await sorts.set(
      '/root/Download',
      const FileSort(FileSortBy.size),
      forAll: true,
    );
    FileSorts s = c.read(fileSortsProvider).value!;
    expect(s.sortFor('/root/Documents').by, FileSortBy.size);
    expect(s.sortFor('/root/Comic/Album').by, FileSortBy.modified);

    await sorts.follow('/root/Comic', '/root/Comics');
    s = c.read(fileSortsProvider).value!;
    expect(s.sortFor('/root/Comics/Album').by, FileSortBy.modified);
  });
}
