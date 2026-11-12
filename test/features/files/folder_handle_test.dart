import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/domain/folder_handle.dart';

FileEntry _e(String name, {int size = 0, DateTime? modified}) => FileEntry(
  path: '/s/$name',
  name: name,
  kind: kindOf(name, isDirectory: !name.contains('.')),
  size: size,
  modified: modified ?? DateTime(2026, 11, 12),
);

void main() {
  String at(List<FileEntry> rows, int i, FileSortBy by, {Set<String>? pins}) =>
      folderHandleLabel(
        rows: rows,
        index: i,
        sort: FileSort(by),
        pins: pins ?? const <String>{},
      );

  test('by name it shows the first letter, # for a digit or symbol', () {
    final List<FileEntry> rows = <FileEntry>[
      _e('Extras'),
      _e('2 Moons.zip'),
      _e('akira.zip'),
      _e('Blame.zip'),
    ];
    expect(at(rows, 0, FileSortBy.name), 'Folders');
    expect(at(rows, 1, FileSortBy.name), '#');
    expect(at(rows, 2, FileSortBy.name), 'A');
    expect(at(rows, 3, FileSortBy.name), 'B');
  });

  test('pinned rows say Pinned whatever the sort', () {
    final List<FileEntry> rows = <FileEntry>[_e('Blame.zip'), _e('Akira.zip')];
    expect(at(rows, 0, FileSortBy.size, pins: {'/s/Blame.zip'}), 'Pinned');
  });

  test('by date the month, by size a band, by type the extension', () {
    final List<FileEntry> rows = <FileEntry>[
      _e('a.zip', size: 2500000000, modified: DateTime(2025, 3, 4)),
      _e('b.pdf', size: 150000000),
      _e('c', size: 0),
      _e('d.cbz', size: 4000000),
      _e('notes.txt', size: 200),
      _e('README', size: 200),
    ]..removeAt(2);
    expect(at(rows, 0, FileSortBy.modified), 'March 2025');
    expect(at(rows, 0, FileSortBy.size), 'Over 1 GB');
    expect(at(rows, 1, FileSortBy.size), '100 MB – 1 GB');
    expect(at(rows, 2, FileSortBy.size), '1 – 10 MB');
    expect(at(rows, 3, FileSortBy.size), 'Under 1 MB');
    expect(at(rows, 2, FileSortBy.type), 'CBZ');
  });

  test('a file with no extension is No type', () {
    final List<FileEntry> rows = <FileEntry>[
      FileEntry(
        path: '/s/README',
        name: 'README',
        kind: FileKind.other,
        size: 1,
        modified: DateTime(2026),
      ),
    ];
    expect(at(rows, 0, FileSortBy.type), 'No type');
  });

  test('an extracted comic counts pages instead, stray info file and all', () {
    final List<FileEntry> rows = <FileEntry>[
      for (int i = 1; i <= 40; i++) _e('${'$i'.padLeft(3, '0')}.jpg'),
      _e('ComicInfo.xml'),
    ];
    expect(at(rows, 36, FileSortBy.name), '37 of 41');
    expect(isPictureFolder(<FileEntry>[_e('Ch 1'), ...rows]), isFalse);
  });
}
