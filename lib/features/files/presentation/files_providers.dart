import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/format/natural_sort.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/storage/preferences.dart';
import '../../albums/presentation/albums_providers.dart';
import '../data/files_repository.dart';
import '../domain/file_entry.dart';

final filesRepositoryProvider = Provider<FilesRepository>(
  (Ref ref) => FilesRepository(ref.watch(nativeChannelProvider)),
);

class FilesAccessNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(nativeChannelProvider).hasAllFilesAccess();

  /// Called on resume: the user may have just flipped the switch in Settings.
  Future<void> recheck() async {
    final bool now = await ref.read(nativeChannelProvider).hasAllFilesAccess();
    if (state.value != now) state = AsyncData<bool>(now);
  }
}

final filesAccessProvider = AsyncNotifierProvider<FilesAccessNotifier, bool>(
  FilesAccessNotifier.new,
);

final storageRootProvider = FutureProvider<String>(
  (Ref ref) => ref.watch(nativeChannelProvider).storageRoot(),
);

final storageStatsProvider = FutureProvider.autoDispose<StorageStats>(
  (Ref ref) => ref.watch(nativeChannelProvider).storage(),
);

final folderProvider = FutureProvider.autoDispose
    .family<List<FileEntry>, String>(
      (Ref ref, String path) => ref.read(filesRepositoryProvider).list(path),
    );

/// A picture from inside a ZIP, to show in place of the archive icon.
/// Kept for the session: reading it means opening the archive, and the
/// rows that ask scroll in and out of view. Keyed by path and size so a
/// replaced file is read again.
final zipCoverProvider = FutureProvider.family<Uint8List?, (String, int)>(
  (Ref ref, (String, int) zip) =>
      // Large enough for the grid view; the list draws it small.
      ref.watch(nativeChannelProvider).zipCover(zip.$1, 400),
);

/// A comic's page count for its tile, or null for a ZIP that isn't one.
/// Keyed by size too, so a rewritten archive is counted again.
final zipPagesProvider = FutureProvider.family<int?, (String, int)>(
  (Ref ref, (String, int) zip) =>
      ref.watch(nativeChannelProvider).zipPageCount(zip.$1),
);

/// The files inside a ZIP, for its contents screen. Invalidated after a
/// delete so the grid reads the rewritten archive.
final zipEntriesProvider = FutureProvider.autoDispose
    .family<List<ZipEntry>, String>(
      (Ref ref, String path) =>
          ref.read(nativeChannelProvider).zipEntries(path),
    );

/// A page from inside a ZIP as a JPEG about px across, keyed by archive
/// path, entry name and px: small for the grid, large for the page viewer.
final zipPageThumbProvider = FutureProvider.autoDispose
    .family<Uint8List?, (String, String, int)>(
      (Ref ref, (String, String, int) key) =>
          ref.read(nativeChannelProvider).zipPageThumb(key.$1, key.$2, key.$3),
    );

/// The first picture directly inside a folder, by natural order (its first
/// page, for an extracted comic), shown in place of the folder icon. Null
/// when the folder holds no pictures of its own, so a parent of comics
/// (Comic, Album) keeps the plain folder icon.
final folderCoverProvider = FutureProvider.autoDispose.family<String?, String>(
  (Ref ref, String dir) => _firstImageIn(dir),
);

Future<String?> _firstImageIn(String dir) async {
  final List<String> images = <String>[];
  try {
    await for (final FileSystemEntity e in Directory(
      dir,
    ).list(followLinks: false)) {
      if (e is File &&
          kindOf(p.basename(e.path), isDirectory: false) == FileKind.image) {
        images.add(e.path);
      }
    }
  } on FileSystemException {
    return null;
  }
  if (images.isEmpty) return null;
  images.sort(naturalCompare);
  return images.first;
}

/// Paths kept in preferences under [key], newest first, that follow their
/// files and folders through renames and moves. A path that has since been
/// deleted is left out by the pages that show it.
abstract class PathPinsNotifier extends AsyncNotifier<List<String>> {
  String get key;

  @override
  Future<List<String>> build() async =>
      await ref.watch(preferencesProvider).getStringList(key) ??
      const <String>[];

  Future<void> _save(List<String> next) async {
    state = AsyncData<List<String>>(next);
    await ref.read(preferencesProvider).setStringList(key, next);
  }

  Future<void> toggle(String path) {
    final List<String> now = state.value ?? const <String>[];
    return _save(
      now.contains(path)
          ? (List<String>.of(now)..remove(path))
          : <String>[path, ...now],
    );
  }

  /// Keeps pins on something renamed or moved from [from] to [to]: its own
  /// pin, and the pins of anything inside it when it is a folder.
  Future<void> follow(String from, String to) async {
    final List<String> now = state.value ?? const <String>[];
    String moved(String path) => path == from
        ? to
        : path.startsWith('$from/')
        ? '$to${path.substring(from.length)}'
        : path;
    final List<String> next = <String>[for (final String p in now) moved(p)];
    if (!listEquals(next, now)) await _save(next);
  }
}

/// Folders added to the Files tab ("Add to Files tab"), shown in its Pinned
/// section wherever they sit. Kept under the key folder pins always used.
class FilesTabPinsNotifier extends PathPinsNotifier {
  @override
  String get key => 'files.pinned';
}

final filesTabPinsProvider =
    AsyncNotifierProvider<FilesTabPinsNotifier, List<String>>(
      FilesTabPinsNotifier.new,
    );

/// Files and folders pinned to the top of their own folder ("Pin to top").
/// They never reach the Files tab, so fifty favourite comics stay in their
/// folder.
class TopPinsNotifier extends PathPinsNotifier {
  @override
  String get key => 'files.top';

  @override
  Future<List<String>> build() async {
    final SharedPreferencesAsync prefs = ref.watch(preferencesProvider);
    final List<String>? saved = await prefs.getStringList(key);
    if (saved != null) return saved;
    // Until 12/11/2026 a pinned file sat with the Files tab's folders; it
    // was a favourite to keep at the top of its folder, so it moves here.
    final List<String> files = <String>[
      for (final String path
          in await prefs.getStringList('files.pinned') ?? const <String>[])
        if (FileSystemEntity.isFileSync(path)) path,
    ];
    await prefs.setStringList(key, files);
    return files;
  }
}

final topPinsProvider = AsyncNotifierProvider<TopPinsNotifier, List<String>>(
  TopPinsNotifier.new,
);

/// How folders in Files are sorted: one default, and the folders given
/// their own order, by path.
class FileSorts {
  const FileSorts({
    this.defaultSort = FileSort.standard,
    this.folders = const <String, FileSort>{},
  });

  final FileSort defaultSort;
  final Map<String, FileSort> folders;

  FileSort sortFor(String dir) => folders[dir] ?? defaultSort;
}

class FileSortsNotifier extends AsyncNotifier<FileSorts> {
  static const String _key = 'files.sort';

  @override
  Future<FileSorts> build() async {
    final String? raw = await ref.watch(preferencesProvider).getString(_key);
    if (raw == null) return const FileSorts();
    final Map<String, Object?> m = jsonDecode(raw) as Map<String, Object?>;
    return FileSorts(
      defaultSort: FileSort.decode(m['default']! as String),
      folders: <String, FileSort>{
        for (final MapEntry<String, Object?> e
            in (m['folders'] as Map<String, Object?>? ?? <String, Object?>{})
                .entries)
          e.key: FileSort.decode(e.value! as String),
      },
    );
  }

  Future<void> _save(FileSorts s) async {
    state = AsyncData<FileSorts>(s);
    await ref
        .read(preferencesProvider)
        .setString(
          _key,
          jsonEncode(<String, Object>{
            'default': s.defaultSort.encode(),
            'folders': <String, String>{
              for (final MapEntry<String, FileSort> e in s.folders.entries)
                e.key: e.value.encode(),
            },
          }),
        );
  }

  FileSorts get _now => state.value ?? const FileSorts();

  /// Sorts [dir] by [sort]; with [forAll], makes it the default instead and
  /// lets [dir] follow it.
  Future<void> set(String dir, FileSort sort, {bool forAll = false}) {
    final FileSorts s = _now;
    return _save(
      forAll
          ? FileSorts(
              defaultSort: sort,
              folders: <String, FileSort>{
                for (final MapEntry<String, FileSort> e in s.folders.entries)
                  if (e.key != dir) e.key: e.value,
              },
            )
          : FileSorts(
              defaultSort: s.defaultSort,
              folders: <String, FileSort>{...s.folders, dir: sort},
            ),
    );
  }

  /// Keeps folders' own sorts through a rename or move of [from] to [to].
  Future<void> follow(String from, String to) async {
    final FileSorts s = _now;
    String moved(String path) => path == from
        ? to
        : path.startsWith('$from/')
        ? '$to${path.substring(from.length)}'
        : path;
    final Map<String, FileSort> next = <String, FileSort>{
      for (final MapEntry<String, FileSort> e in s.folders.entries)
        moved(e.key): e.value,
    };
    if (!mapEquals(next, s.folders)) {
      await _save(FileSorts(defaultSort: s.defaultSort, folders: next));
    }
  }
}

final fileSortsProvider = AsyncNotifierProvider<FileSortsNotifier, FileSorts>(
  FileSortsNotifier.new,
);

/// What is typed in a folder's search field, by folder path. Held here, not
/// in the field's widget, because the bar above the list needs it too:
/// Select all must select what the search is showing.
class FolderQuery extends Notifier<String> {
  FolderQuery(this.dir);
  final String dir;

  @override
  String build() => '';

  void set(String query) => state = query;
}

final folderQueryProvider = NotifierProvider.autoDispose
    .family<FolderQuery, String, String>(FolderQuery.new);

/// A picture or video file's thumbnail for its tile or row, keyed by path
/// and size in pixels.
///
/// A tile asks only once it has stayed on screen for a moment, so the rows
/// a fling or the scroll handle passes over cost nothing. Thumbnails seen
/// recently are kept for two minutes, so scrolling back doesn't load them
/// again.
final fileThumbProvider = FutureProvider.autoDispose
    .family<Uint8List?, (String, int)>((Ref ref, (String, int) key) async {
      final NativeChannel native = ref.read(nativeChannelProvider);
      bool gone = false;
      ref.onDispose(() => gone = true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (gone) return null;
      final Uint8List? bytes = await native.thumbnail(key.$1, key.$2);
      final link = ref.keepAlive();
      Timer? release;
      ref.onCancel(
        () => release = Timer(const Duration(minutes: 2), link.close),
      );
      ref.onResume(() => release?.cancel());
      ref.onDispose(() => release?.cancel());
      return bytes;
    });

/// Whether folders are shown as a grid of pictures instead of a list of
/// rows. One choice for every folder, remembered between sessions.
class FilesGridNotifier extends AsyncNotifier<bool> {
  static const String _key = 'files.grid';

  @override
  Future<bool> build() async =>
      await ref.watch(preferencesProvider).getBool(_key) ?? false;

  Future<void> toggle() async {
    final bool next = !(state.value ?? false);
    state = AsyncData<bool>(next);
    await ref.read(preferencesProvider).setBool(_key, next);
  }
}

final filesGridProvider = AsyncNotifierProvider<FilesGridNotifier, bool>(
  FilesGridNotifier.new,
);
