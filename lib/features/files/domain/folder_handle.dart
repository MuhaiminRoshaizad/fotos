import '../../../core/format/formatters.dart';
import 'file_entry.dart';

/// What a folder's scroll handle says over one row: [primary] large,
/// [secondary] small under it, and the [mark] on the track that row
/// belongs to (none for a position in a comic, where marks say nothing).
typedef FolderHandleLabel = ({String primary, String? secondary, String? mark});

/// Folder types beyond this many are too many to line the track with.
const int _maxTypeMarks = 12;

/// The handle's label for each of [rows], the folder as shown, sorted by
/// [sort]. Each names what that sort orders by, so the handle only ever
/// shows letters, months, sizes or types the folder actually has.
List<FolderHandleLabel> folderHandleLabels({
  required List<FileEntry> rows,
  required FileSort sort,
  required Set<String> pins,
}) {
  // An extracted comic: its pages are 001.jpg, 002.jpg, so a letter says
  // nothing, but how far in you are does.
  if (isPictureFolder(rows)) {
    return <FolderHandleLabel>[
      for (int i = 0; i < rows.length; i++)
        (primary: '${i + 1}', secondary: 'of ${rows.length}', mark: null),
    ];
  }
  final List<FileEntry> files = <FileEntry>[
    for (final FileEntry e in rows)
      if (!e.isFolder && !pins.contains(e.path)) e,
  ];
  final bool oneYear =
      files.map((FileEntry e) => e.modified.year).toSet().length <= 1;
  final bool fewTypes =
      files.map((FileEntry e) => _type(e.name)).toSet().length <= _maxTypeMarks;
  return <FolderHandleLabel>[
    for (final FileEntry e in rows)
      if (pins.contains(e.path))
        (primary: 'Pinned', secondary: null, mark: 'Pinned')
      else if (e.isFolder)
        (primary: 'Folders', secondary: null, mark: 'Folders')
      else
        switch (sort.by) {
          FileSortBy.name => (
            primary: _initial(e.name),
            secondary: null,
            mark: _initial(e.name),
          ),
          FileSortBy.modified => (
            primary: Fmt.months[e.modified.month - 1],
            secondary: '${e.modified.year}',
            mark: oneYear
                ? Fmt.months[e.modified.month - 1]
                : '${e.modified.year}',
          ),
          FileSortBy.size => (
            primary: _sizeBand(e.size),
            secondary: null,
            mark: _sizeBand(e.size),
          ),
          FileSortBy.type => (
            primary: _type(e.name),
            secondary: null,
            mark: fewTypes ? _type(e.name) : null,
          ),
        },
  ];
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

String _type(String name) {
  final String ext = extensionOf(name);
  return ext.isEmpty ? 'No type' : ext.toUpperCase();
}

String _sizeBand(int bytes) {
  if (bytes >= 1000000000) return 'Over 1 GB';
  if (bytes >= 100000000) return '100 MB – 1 GB';
  if (bytes >= 10000000) return '10 – 100 MB';
  if (bytes >= 1000000) return '1 – 10 MB';
  return 'Under 1 MB';
}
