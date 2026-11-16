import '../../../core/format/natural_sort.dart';

/// How the Files tab treats a file when it is tapped.
enum FileKind { folder, image, video, pdf, zip, text, other }

const Set<String> _image = <String>{
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'dng', 'avif', //
};
const Set<String> _video = <String>{
  'mp4', 'mov', 'm4v', 'mkv', 'webm', '3gp', 'avi', //
};
const Set<String> _text = <String>{
  'txt', 'md', 'json', 'csv', 'log', 'xml', 'yaml', 'yml', 'ini', //
};

String extensionOf(String name) {
  final int dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

FileKind kindOf(String name, {required bool isDirectory}) {
  if (isDirectory) return FileKind.folder;
  final String ext = extensionOf(name);
  if (_image.contains(ext)) return FileKind.image;
  if (_video.contains(ext)) return FileKind.video;
  if (ext == 'pdf') return FileKind.pdf;
  // .cbz is a comic archive — a ZIP by another name.
  if (ext == 'zip' || ext == 'cbz') return FileKind.zip;
  if (_text.contains(ext)) return FileKind.text;
  return FileKind.other;
}

/// A file or folder as listed in the Files tab.
class FileEntry {
  const FileEntry({
    required this.path,
    required this.name,
    required this.kind,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final FileKind kind;
  final int size;
  final DateTime modified;

  bool get isFolder => kind == FileKind.folder;
  bool get isMedia => kind == FileKind.image || kind == FileKind.video;
}

/// Folders first, then files, each in natural name order (page 2 before
/// page 10).
int compareEntries(FileEntry a, FileEntry b) {
  if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
  return naturalCompare(a.name, b.name);
}

enum FileSortBy {
  name('Name'),
  // Android keeps no date a file arrived, only when it last changed; for a
  // download or an extracted comic that is the day it came.
  modified('Date modified'),
  size('Size'),
  type('Type');

  const FileSortBy(this.label);
  final String label;

  /// Labels for the two directions, first being the default.
  (String, String) get directions => switch (this) {
    FileSortBy.name => ('A to Z', 'Z to A'),
    FileSortBy.modified => ('Newest first', 'Oldest first'),
    FileSortBy.size => ('Largest first', 'Smallest first'),
    FileSortBy.type => ('A to Z', 'Z to A'),
  };
}

/// How a folder in Files is ordered. Folders always come before files;
/// each part is sorted by [by], ties broken by name.
class FileSort {
  const FileSort(this.by, {this.reversed = false});

  final FileSortBy by;

  /// False means the first of [FileSortBy.directions].
  final bool reversed;

  static const FileSort standard = FileSort(FileSortBy.name);

  String encode() => '${by.name}:${reversed ? 1 : 0}';

  static FileSort decode(String s) {
    final List<String> p = s.split(':');
    return FileSort(
      FileSortBy.values.firstWhere(
        (FileSortBy b) => b.name == p.first,
        orElse: () => FileSortBy.name,
      ),
      reversed: p.length > 1 && p[1] == '1',
    );
  }

  List<FileEntry> apply(List<FileEntry> entries) {
    int byName(FileEntry a, FileEntry b) => naturalCompare(a.name, b.name);
    int key(FileEntry a, FileEntry b) => switch (by) {
      FileSortBy.name => byName(a, b),
      FileSortBy.modified => b.modified.compareTo(a.modified),
      FileSortBy.size => b.size.compareTo(a.size),
      FileSortBy.type => extensionOf(a.name).compareTo(extensionOf(b.name)),
    };
    int compare(FileEntry a, FileEntry b) {
      final int c = reversed ? key(b, a) : key(a, b);
      return c != 0 ? c : byName(a, b);
    }

    return <FileEntry>[
      ...entries.where((FileEntry e) => e.isFolder).toList()..sort(compare),
      ...entries.where((FileEntry e) => !e.isFolder).toList()..sort(compare),
    ];
  }
}

/// [entries] with the pinned ones moved to the top, each part keeping its
/// order (folders first, then A to Z).
List<FileEntry> pinnedFirst(List<FileEntry> entries, Set<String> pinned) {
  if (pinned.isEmpty) return entries;
  return <FileEntry>[
    ...entries.where((FileEntry e) => pinned.contains(e.path)),
    ...entries.where((FileEntry e) => !pinned.contains(e.path)),
  ];
}

/// A free name for a copy or extraction: "holiday", then "holiday (2)" ...
String uniqueName(String wanted, Set<String> taken) {
  final Set<String> lower = taken.map((String t) => t.toLowerCase()).toSet();
  if (!lower.contains(wanted.toLowerCase())) return wanted;
  final String ext = extensionOf(wanted);
  final String stem = ext.isEmpty
      ? wanted
      : wanted.substring(0, wanted.length - ext.length - 1);
  for (int i = 2; ; i++) {
    final String candidate = ext.isEmpty ? '$stem ($i)' : '$stem ($i).$ext';
    if (!lower.contains(candidate.toLowerCase())) return candidate;
  }
}

/// The folder every one of [names] (a ZIP's file entries) sits inside, with
/// its trailing slash, e.g. "Comic A/"; null when the files are loose or
/// spread over several folders. Extracting strips it, because the ZIP already
/// gets a folder of its own name and a comic zipped as its folder would
/// otherwise land as Comic A/Comic A/.
String? sharedTopFolder(Iterable<String> names) {
  String? top;
  for (final String name in names) {
    final int slash = name.indexOf('/');
    if (slash <= 0) return null;
    final String folder = name.substring(0, slash + 1);
    if (top != null && folder != top) return null;
    top = folder;
  }
  return top;
}

/// The image among [paths] that stands for a comic — its first page, by
/// natural name order, the same page a ZIP shows as its cover. Null when none
/// of [paths] is an image. Whole paths are compared, so pages nested in a
/// folder (comic/001.jpg) still order before comic/010.jpg.
String? firstImagePath(Iterable<String> paths) {
  final List<String> images = <String>[
    for (final String path in paths)
      if (kindOf(path, isDirectory: false) == FileKind.image) path,
  ]..sort(naturalCompare);
  return images.isEmpty ? null : images.first;
}

/// The entries whose name contains [query], ignoring case; all of them for
/// an empty query. What a folder's search field shows, and so what its
/// Select all selects.
List<FileEntry> filterByName(List<FileEntry> entries, String query) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;
  return <FileEntry>[
    for (final FileEntry e in entries)
      if (e.name.toLowerCase().contains(q)) e,
  ];
}
