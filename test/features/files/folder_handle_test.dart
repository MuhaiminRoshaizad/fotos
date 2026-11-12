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
  List<FolderHandleLabel> labels(
    List<FileEntry> rows,
    FileSortBy by, {
    Set<String> pins = const <String>{},
  }) => folderHandleLabels(rows: rows, sort: FileSort(by), pins: pins);

  test('by name: the first letter, # for a digit, marked by letter', () {
    final List<FolderHandleLabel> l = labels(<FileEntry>[
      _e('Extras'),
      _e('2 Moons.zip'),
      _e('akira.zip'),
      _e('Blame.zip'),
    ], FileSortBy.name);
    expect(l.map((FolderHandleLabel x) => x.primary), <String>[
      'Folders',
      '#',
      'A',
      'B',
    ]);
    expect(l.map((FolderHandleLabel x) => x.mark), <String>[
      'Folders',
      '#',
      'A',
      'B',
    ]);
  });

  test('pinned rows say Pinned whatever the sort', () {
    final List<FolderHandleLabel> l = labels(
      <FileEntry>[_e('Blame.zip'), _e('Akira.zip')],
      FileSortBy.size,
      pins: <String>{'/s/Blame.zip'},
    );
    expect(l.first, (primary: 'Pinned', secondary: null, mark: 'Pinned'));
  });

  test('by date: month over year, marked by year, or by month in one year', () {
    final List<FolderHandleLabel> years = labels(<FileEntry>[
      _e('a.zip', modified: DateTime(2026, 3, 4)),
      _e('b.zip', modified: DateTime(2025, 7, 1)),
    ], FileSortBy.modified);
    expect(years.first, (primary: 'March', secondary: '2026', mark: '2026'));
    final List<FolderHandleLabel> oneYear = labels(<FileEntry>[
      _e('a.zip', modified: DateTime(2026, 3, 4)),
      _e('b.zip', modified: DateTime(2026, 7, 1)),
    ], FileSortBy.modified);
    expect(oneYear.last.mark, 'July');
  });

  test('by size: the band; by type: the extension, unmarked past 12 types', () {
    final List<FolderHandleLabel> size = labels(<FileEntry>[
      _e('a.zip', size: 2500000000),
      _e('b.pdf', size: 150000000),
      _e('d.cbz', size: 4000000),
      _e('notes.txt', size: 200),
    ], FileSortBy.size);
    expect(size.map((FolderHandleLabel x) => x.primary), <String>[
      'Over 1 GB',
      '100 MB – 1 GB',
      '1 – 10 MB',
      'Under 1 MB',
    ]);
    final List<FolderHandleLabel> types = labels(<FileEntry>[
      _e('a.cbz'),
      FileEntry(
        path: '/s/README',
        name: 'README',
        kind: FileKind.other,
        size: 1,
        modified: DateTime(2026),
      ),
    ], FileSortBy.type);
    expect(types.map((FolderHandleLabel x) => x.primary), <String>[
      'CBZ',
      'No type',
    ]);
    final List<FolderHandleLabel> many = labels(<FileEntry>[
      for (int i = 0; i < 13; i++) _e('f.x$i'),
    ], FileSortBy.type);
    expect(many.first.mark, isNull);
  });

  test('an extracted comic counts pages, with no marks', () {
    final List<FileEntry> rows = <FileEntry>[
      for (int i = 1; i <= 40; i++) _e('${'$i'.padLeft(3, '0')}.jpg'),
      _e('ComicInfo.xml'),
    ];
    final FolderHandleLabel l = labels(rows, FileSortBy.name)[36];
    expect(l, (primary: '37', secondary: 'of 41', mark: null));
    expect(isPictureFolder(<FileEntry>[_e('Ch 1'), ...rows]), isFalse);
  });
}
