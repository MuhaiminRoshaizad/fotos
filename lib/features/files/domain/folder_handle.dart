import '../../../core/format/formatters.dart';
import 'file_entry.dart';

/// What a folder's scroll handle says over the row at [index] of [rows],
/// the folder as shown, sorted by [sort]. It names what that sort orders
/// by, so it only ever shows letters, months, sizes or types the folder
/// actually has.
String folderHandleLabel({
  required List<FileEntry> rows,
  required int index,
  required FileSort sort,
  required Set<String> pins,
}) {
  if (rows.isEmpty) return '';
  final FileEntry e = rows[index.clamp(0, rows.length - 1)];
  // An extracted comic: its pages are 001.jpg, 002.jpg, so a letter says
  // nothing, but how far in you are does.
  if (isPictureFolder(rows)) return '${index + 1} of ${rows.length}';
  if (pins.contains(e.path)) return 'Pinned';
  if (e.isFolder) return 'Folders';
  return switch (sort.by) {
    FileSortBy.name => _initial(e.name),
    FileSortBy.modified => Fmt.monthYear(e.modified),
    FileSortBy.size => _sizeBand(e.size),
    FileSortBy.type =>
      extensionOf(e.name).isEmpty
          ? 'No type'
          : extensionOf(e.name).toUpperCase(),
  };
}

/// A folder of pictures and nothing else of note: no folders, and mostly
/// images (an extracted comic may carry a stray info file).
bool isPictureFolder(List<FileEntry> rows) {
  if (rows.any((FileEntry e) => e.isFolder)) return false;
  final int pictures = rows
      .where((FileEntry e) => e.kind == FileKind.image)
      .length;
  return pictures * 2 > rows.length;
}

String _initial(String name) {
  final String first = name.isEmpty ? '' : name[0].toUpperCase();
  return RegExp('[A-Z]').hasMatch(first) ? first : '#';
}

String _sizeBand(int bytes) {
  if (bytes >= 1000000000) return 'Over 1 GB';
  if (bytes >= 100000000) return '100 MB – 1 GB';
  if (bytes >= 10000000) return '10 – 100 MB';
  if (bytes >= 1000000) return '1 – 10 MB';
  return 'Under 1 MB';
}
