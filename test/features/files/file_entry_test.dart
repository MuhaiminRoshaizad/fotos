import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';

FileEntry _e(String name, {bool dir = false}) => FileEntry(
  path: '/x/$name',
  name: name,
  kind: kindOf(name, isDirectory: dir),
  size: 0,
  modified: DateTime(2026),
);

void main() {
  test('kindOf maps extensions case-insensitively', () {
    expect(kindOf('IMG_0300.JPG', isDirectory: false), FileKind.image);
    expect(kindOf('PXL_1.heic', isDirectory: false), FileKind.image);
    expect(kindOf('clip.MOV', isDirectory: false), FileKind.video);
    expect(kindOf('Offer letter.pdf', isDirectory: false), FileKind.pdf);
    expect(kindOf('takeout-1.zip', isDirectory: false), FileKind.zip);
    expect(kindOf('notes.txt', isDirectory: false), FileKind.text);
    expect(kindOf('Tenancy.docx', isDirectory: false), FileKind.other);
    expect(kindOf('noext', isDirectory: false), FileKind.other);
    expect(kindOf('Download', isDirectory: true), FileKind.folder);
  });

  test('folders sort before files, then A to Z', () {
    final List<FileEntry> list = <FileEntry>[
      _e('b.txt'),
      _e('Zeta', dir: true),
      _e('a.pdf'),
      _e('alpha', dir: true),
    ]..sort(compareEntries);
    expect(list.map((FileEntry e) => e.name), <String>[
      'alpha',
      'Zeta',
      'a.pdf',
      'b.txt',
    ]);
  });

  test('files sort in natural number order, folders still first', () {
    final List<FileEntry> list = <FileEntry>[
      _e('10.jpg'),
      _e('2.jpg'),
      _e('scans', dir: true),
      _e('1.jpg'),
    ]..sort(compareEntries);
    expect(list.map((FileEntry e) => e.name), <String>[
      'scans',
      '1.jpg',
      '2.jpg',
      '10.jpg',
    ]);
  });

  test('uniqueName numbers clashes and keeps the extension', () {
    expect(uniqueName('holiday', <String>{}), 'holiday');
    expect(uniqueName('holiday', <String>{'Holiday'}), 'holiday (2)');
    expect(uniqueName('a.pdf', <String>{'a.pdf', 'a (2).pdf'}), 'a (3).pdf');
  });
}
