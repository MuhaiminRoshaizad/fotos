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
    expect(kindOf('One Piece v1.CBZ', isDirectory: false), FileKind.zip);
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

  test('firstImagePath picks the first page, ignoring non-images', () {
    expect(
      firstImagePath(<String>[
        '/c/Comic/info.txt',
        '/c/Comic/10.jpg',
        '/c/Comic/2.jpg',
        '/c/Comic/cover.png',
        '/c/Comic/1.jpg',
      ]),
      '/c/Comic/1.jpg',
    );
  });

  test('firstImagePath orders pages nested in a folder', () {
    expect(
      firstImagePath(<String>['/c/Comic/010.jpg', '/c/Comic/002.jpg']),
      '/c/Comic/002.jpg',
    );
  });

  test('firstImagePath is null when nothing is an image', () {
    expect(firstImagePath(<String>['/c/a.txt', '/c/notes.pdf']), isNull);
  });

  test('sharedTopFolder finds the one folder a comic was zipped as', () {
    // Extracting into "Comic A" must not give Comic A/Comic A/001.jpg.
    expect(
      sharedTopFolder(<String>['Comic A/001.jpg', 'Comic A/sub/002.jpg']),
      'Comic A/',
    );
  });

  test('sharedTopFolder is null for loose or mixed files', () {
    expect(sharedTopFolder(<String>['001.jpg', '002.jpg']), isNull);
    expect(sharedTopFolder(<String>['Comic A/001.jpg', 'cover.jpg']), isNull);
    expect(sharedTopFolder(<String>['A/001.jpg', 'B/001.jpg']), isNull);
    expect(sharedTopFolder(<String>[]), isNull);
  });

  test('uniqueName numbers clashes and keeps the extension', () {
    expect(uniqueName('holiday', <String>{}), 'holiday');
    expect(uniqueName('holiday', <String>{'Holiday'}), 'holiday (2)');
    expect(uniqueName('a.pdf', <String>{'a.pdf', 'a (2).pdf'}), 'a (3).pdf');
  });
}
