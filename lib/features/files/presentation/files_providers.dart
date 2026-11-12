import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

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

/// Files and folders the user pinned, newest pin first. They are listed at
/// the top of the Files tab and first in their own folder. Paths, kept in
/// preferences under the key folder pins always used; one that has since
/// been deleted or moved is left out by the pages that show them.
class PinnedNotifier extends AsyncNotifier<List<String>> {
  static const String _key = 'files.pinned';

  @override
  Future<List<String>> build() async =>
      await ref.watch(preferencesProvider).getStringList(_key) ??
      const <String>[];

  Future<void> toggle(String path) async {
    final List<String> now = state.value ?? const <String>[];
    final List<String> next = now.contains(path)
        ? (List<String>.of(now)..remove(path))
        : <String>[path, ...now];
    state = AsyncData<List<String>>(next);
    await ref.read(preferencesProvider).setStringList(_key, next);
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
    if (listEquals(next, now)) return;
    state = AsyncData<List<String>>(next);
    await ref.read(preferencesProvider).setStringList(_key, next);
  }
}

final pinnedProvider = AsyncNotifierProvider<PinnedNotifier, List<String>>(
  PinnedNotifier.new,
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

/// A frame from a video file, for its tile in the grid view. Kept for the
/// session, keyed like [zipCoverProvider].
final videoFrameProvider = FutureProvider.family<Uint8List?, (String, int)>(
  (Ref ref, (String, int) video) =>
      ref.watch(nativeChannelProvider).videoFrame(video.$1, 400),
);

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
