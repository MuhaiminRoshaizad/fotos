import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fotos_cover');
    // Comic/Album/<comic>/<pages>, as the owner keeps them.
    final Directory comic = await Directory(
      p.join(root.path, 'Comic', 'Album', 'Iron Orchard'),
    ).create(recursive: true);
    for (final String page in <String>[
      '10.jpg',
      '2.jpg',
      '1.jpg',
      'info.txt',
    ]) {
      await File(p.join(comic.path, page)).writeAsString('x');
    }
  });
  tearDown(() => root.delete(recursive: true));

  test('only a folder holding pictures itself shows one; its parents keep '
      'the folder icon', () async {
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    String? cover(String rel) =>
        c.read(folderCoverProvider(p.join(root.path, rel))).value;
    for (final String rel in <String>[
      'Comic',
      p.join('Comic', 'Album'),
      p.join('Comic', 'Album', 'Iron Orchard'),
    ]) {
      // Keep each one alive while it loads.
      c.listen(folderCoverProvider(p.join(root.path, rel)), (_, _) {});
      await c.read(folderCoverProvider(p.join(root.path, rel)).future);
    }
    expect(cover('Comic'), isNull);
    expect(cover(p.join('Comic', 'Album')), isNull);
    expect(
      p.basename(cover(p.join('Comic', 'Album', 'Iron Orchard'))!),
      '1.jpg',
    );
  });
}
