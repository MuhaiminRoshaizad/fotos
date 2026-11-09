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
  if (ext == 'zip') return FileKind.zip;
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

/// Folders first, then files, each A to Z ignoring case.
int compareEntries(FileEntry a, FileEntry b) {
  if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
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
