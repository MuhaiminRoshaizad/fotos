import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/read_mode.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/file_media_viewer.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/viewer/presentation/strip_viewer.dart';
import 'package:path/path.dart' as p;

/// A 1x1 grey PNG.
final List<int> _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
);

/// The comic's folder, read in [mode].
class _Modes extends ReadModesNotifier {
  _Modes(this.mode);
  final ReadMode mode;

  @override
  Future<Map<String, ReadMode>> build() async => <String, ReadMode>{
    'Comic/Album/Iron Orchard': mode,
  };
}

void main() {
  late Directory root;
  late List<FileEntry> pages;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fotos_read');
    final Directory comic = await Directory(
      p.join(root.path, 'Comic', 'Album', 'Iron Orchard'),
    ).create(recursive: true);
    pages = <FileEntry>[
      for (final String n in <String>['1.png', '2.png', '3.png'])
        FileEntry(
          path: (await File(p.join(comic.path, n)).writeAsBytes(_pixel)).path,
          name: n,
          kind: FileKind.image,
          size: _pixel.length,
          modified: DateTime(2026, 11, 12),
        ),
    ];
  });
  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Windows holds a picture a moment after the test lets go of it.
    }
  });

  Future<void> open(WidgetTester tester, ReadMode mode) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRootProvider.overrideWith((Ref ref) async => root.path),
          readModesProvider.overrideWith(() => _Modes(mode)),
        ],
        child: MaterialApp(home: FileMediaViewer(items: pages, index: 0)),
      ),
    );
    // Reading the pictures' headers is real file work, one picture after
    // another: let it run and the screen catch up, a few times over.
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a folder read as pages turns on a tap at the right edge from '
      'Files too', (WidgetTester tester) async {
    await open(tester, ReadMode.pages);
    await tester.tapAt(const Offset(370, 400));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final PageView view = tester.widget(find.byType(PageView));
    expect(view.controller!.page, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a folder read as a strip opens as one from Files too', (
    WidgetTester tester,
  ) async {
    await open(tester, ReadMode.strip);
    expect(find.byType(StripViewer), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Iron Orchard'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
