import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/platform/native_channel.dart';
import 'package:fotos/features/files/data/files_repository.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FilesRepository repo;

  FileEntry file(String dir, String name) {
    final File f = File(p.join(dir, name))..writeAsStringSync(name);
    return FileEntry(
      path: f.path,
      name: name,
      kind: kindOf(name, isDirectory: false),
      size: f.lengthSync(),
      modified: DateTime(2026, 11, 11),
    );
  }

  setUp(() {
    // Moves and copies ask Android to rescan; there is nothing to answer.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('my.minned.fotos/native'),
          (_) async => null,
        );
    root = Directory.systemTemp.createTempSync('fotos-files-');
    Directory(p.join(root.path, 'from')).createSync();
    Directory(p.join(root.path, 'other')).createSync();
    Directory(p.join(root.path, 'to')).createSync();
    repo = FilesRepository(NativeChannel());
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('namesIn lists every name, hidden ones too', () async {
    final String dir = p.join(root.path, 'from');
    file(dir, 'a.zip');
    file(dir, '.nomedia');
    expect(await repo.namesIn(dir), <String>{'a.zip', '.nomedia'});
  });

  test(
    'a batch sharing one set of names keeps same-named files apart',
    () async {
      final String to = p.join(root.path, 'to');
      file(to, 'comic.zip');
      final FileEntry first = file(p.join(root.path, 'from'), 'comic.zip');
      final FileEntry second = file(p.join(root.path, 'other'), 'comic.zip');

      // Read once for the whole batch, as a large move does.
      final Set<String> taken = await repo.namesIn(to);
      final String a = await repo.moveTo(first, to, taken: taken);
      final String b = await repo.moveTo(second, to, taken: taken);

      expect(<String>{p.basename(a), p.basename(b)}, hasLength(2));
      expect(p.basename(a), isNot('comic.zip'));
      expect(Directory(to).listSync(), hasLength(3));
      expect(File(first.path).existsSync(), isFalse);
      expect(File(p.join(to, 'comic.zip')).readAsStringSync(), 'comic.zip');
    },
  );

  test('copying leaves the original where it was', () async {
    final String to = p.join(root.path, 'to');
    final FileEntry e = file(p.join(root.path, 'from'), 'notes.txt');
    final String copy = await repo.copyTo(e, to);
    expect(File(copy).existsSync(), isTrue);
    expect(File(e.path).existsSync(), isTrue);
  });
}
