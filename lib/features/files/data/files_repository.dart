import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/platform/native_channel.dart';
import '../domain/file_entry.dart';

/// The phone's shared storage, read and changed with plain file APIs (which
/// All files access permits), keeping MediaStore in step after every change.
class FilesRepository {
  const FilesRepository(this._native);

  final NativeChannel _native;

  Future<List<FileEntry>> list(String dir) async {
    final List<FileEntry> out = <FileEntry>[];
    await for (final FileSystemEntity e in Directory(
      dir,
    ).list(followLinks: false)) {
      final String name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      final FileStat s = await e.stat();
      final bool isDir = s.type == FileSystemEntityType.directory;
      out.add(
        FileEntry(
          path: e.path,
          name: name,
          kind: kindOf(name, isDirectory: isDir),
          size: isDir ? 0 : s.size,
          modified: s.modified,
        ),
      );
    }
    out.sort(compareEntries);
    return out;
  }

  /// The names in [dir], hidden ones included, without reading each
  /// entry's size and date as [list] does.
  Future<Set<String>> namesIn(String dir) async => <String>{
    await for (final FileSystemEntity e in Directory(
      dir,
    ).list(followLinks: false))
      p.basename(e.path),
  };

  Future<String> createFolder(String parent, String name) async {
    final Directory d = await Directory(p.join(parent, name)).create();
    return d.path;
  }

  Future<String> rename(FileEntry e, String newName) async {
    final String target = p.join(p.dirname(e.path), newName);
    final FileSystemEntity moved = e.isFolder
        ? await Directory(e.path).rename(target)
        : await File(e.path).rename(target);
    await _native.scan(<String>[e.path, moved.path]);
    return moved.path;
  }

  /// Deleting here is permanent: shared storage has no trash for non-media
  /// files, which is why the UI always confirms first.
  Future<void> delete(FileEntry e) async {
    final List<String> media = await _mediaUnder(e);
    if (e.isFolder) {
      await Directory(e.path).delete(recursive: true);
    } else {
      await File(e.path).delete();
    }
    await _native.scan(media);
  }

  /// [taken] is the names already in [targetDir], for a caller placing
  /// many entries: it is read once and kept up to date here, where reading
  /// the folder again for every entry made a large move crawl.
  Future<String> copyTo(
    FileEntry e,
    String targetDir, {
    Set<String>? taken,
  }) async {
    final Set<String> names = taken ?? await namesIn(targetDir);
    final String name = uniqueName(e.name, names);
    names.add(name);
    final String target = p.join(targetDir, name);
    if (e.isFolder) {
      await _copyDir(Directory(e.path), Directory(target));
    } else {
      await File(e.path).copy(target);
    }
    await _native.scan(await _mediaUnder(_entry(target, e)));
    return target;
  }

  Future<String> moveTo(
    FileEntry e,
    String targetDir, {
    Set<String>? taken,
  }) async {
    final Set<String> names = taken ?? await namesIn(targetDir);
    final String name = uniqueName(e.name, names);
    names.add(name);
    final String target = p.join(targetDir, name);
    final List<String> before = await _mediaUnder(e);
    // Same volume, so a rename moves without copying the bytes.
    if (e.isFolder) {
      await Directory(e.path).rename(target);
    } else {
      await File(e.path).rename(target);
    }
    await _native.scan(<String>[
      ...before,
      ...await _mediaUnder(_entry(target, e)),
    ]);
    return target;
  }

  FileEntry _entry(String path, FileEntry like) => FileEntry(
    path: path,
    name: p.basename(path),
    kind: like.kind,
    size: like.size,
    modified: like.modified,
  );

  Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final FileSystemEntity e in from.list(followLinks: false)) {
      final String dest = p.join(to.path, p.basename(e.path));
      if (e is Directory) {
        await _copyDir(e, Directory(dest));
      } else if (e is File) {
        await e.copy(dest);
      }
    }
  }

  /// Media paths at or under [e], which MediaStore must re-scan.
  Future<List<String>> _mediaUnder(FileEntry e) async {
    if (!e.isFolder) return e.isMedia ? <String>[e.path] : <String>[];
    final List<String> out = <String>[];
    final Directory d = Directory(e.path);
    if (!await d.exists()) return out;
    await for (final FileSystemEntity f in d.list(
      recursive: true,
      followLinks: false,
    )) {
      if (f is File) {
        final FileKind k = kindOf(p.basename(f.path), isDirectory: false);
        if (k == FileKind.image || k == FileKind.video) out.add(f.path);
      }
    }
    return out;
  }
}
