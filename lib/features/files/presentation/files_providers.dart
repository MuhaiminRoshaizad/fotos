import 'dart:io';
import 'dart:typed_data';

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

/// The first image inside a folder, by natural order (its first page for a
/// comic), to show as the folder's tile instead of a plain folder icon. Null
/// when the folder holds no images. Looks into subfolders so a comic whose
/// pages sit one level down still gets a cover.
final folderCoverProvider = FutureProvider.autoDispose.family<String?, String>(
  (Ref ref, String dir) => _firstImageUnder(dir),
);

/// The first image under [dir] by natural order, searching subfolders. Bounded
/// — at most [budget] folders are opened and [maxDepth] deep — so a huge tree
/// (DCIM, Android) can't stall the Files list; it just shows the folder icon.
Future<String?> _firstImageUnder(
  String dir, {
  int maxDepth = 4,
  int budget = 48,
}) async {
  Future<String?> walk(String d, int depth) async {
    if (depth > maxDepth || budget <= 0) return null;
    budget--;
    final List<String> images = <String>[];
    final List<String> subdirs = <String>[];
    try {
      await for (final FileSystemEntity e in Directory(
        d,
      ).list(followLinks: false)) {
        if (e is File) {
          if (kindOf(p.basename(e.path), isDirectory: false) ==
              FileKind.image) {
            images.add(e.path);
          }
        } else if (e is Directory) {
          subdirs.add(e.path);
        }
      }
    } on FileSystemException {
      return null;
    }
    if (images.isNotEmpty) {
      images.sort(naturalCompare);
      return images.first;
    }
    subdirs.sort(naturalCompare);
    for (final String sub in subdirs) {
      final String? found = await walk(sub, depth + 1);
      if (found != null) return found;
      if (budget <= 0) break;
    }
    return null;
  }

  return walk(dir, 0);
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
