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
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fotos_case');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('my.minned.fotos/native'),
          (MethodCall call) async => null,
        );
  });
  tearDown(() => root.delete(recursive: true));

  test('renaming a folder in letter case only changes its name, and leaves '
      'nothing behind', () async {
    final Directory clips = await Directory(
      p.join(root.path, 'CVR clips'),
    ).create();
    await File(p.join(clips.path, 'clip.mp4')).writeAsString('x');
    const FilesRepository repo = FilesRepository(NativeChannel());
    final FileEntry entry = repo.entryAtSync(clips.path)!;

    final String to = await repo.rename(entry, 'cvr clips');

    expect(p.basename(to), 'cvr clips');
    final List<String> names = <String>[
      for (final FileSystemEntity e in root.listSync()) p.basename(e.path),
    ];
    expect(names, <String>['cvr clips']);
    expect(File(p.join(to, 'clip.mp4')).existsSync(), isTrue);
  });
}
