import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/selection/selection.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/file_actions.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/files_selection.dart';
import 'package:path/path.dart' as p;

FileEntry _entry(String dir, String name, {bool folder = false}) => FileEntry(
  path: p.join(dir, name),
  name: name,
  kind: kindOf(name, isDirectory: folder),
  size: 10,
  modified: DateTime(2026, 11, 16),
);

void main() {
  late Directory dir;
  final List<MethodCall> extracts = <MethodCall>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('extract_many');
    extracts.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('my.minned.fotos/native'),
          (MethodCall call) async {
            switch (call.method) {
              case 'zipEntries':
                // Each comic was zipped as its own folder.
                final String stem = p.basenameWithoutExtension(
                  (call.arguments as Map<Object?, Object?>)['path']! as String,
                );
                return <Map<String, Object>>[
                  for (final String page in <String>['001.jpg', '002.jpg'])
                    <String, Object>{
                      'name': '$stem/$page',
                      'size': 1,
                      'isImage': true,
                    },
                ];
              case 'extract':
                extracts.add(call);
                return 0;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('my.minned.fotos/native'),
          null,
        );
    dir.deleteSync(recursive: true);
  });

  testWidgets('Extract is offered only while every item selected is a ZIP', (
    WidgetTester tester,
  ) async {
    final List<FileEntry> entries = <FileEntry>[
      _entry('/root', 'Comics', folder: true),
      _entry('/root', 'A.zip'),
      _entry('/root', 'B.zip'),
      _entry('/root', 'notes.txt'),
    ];
    late List<SelectionAction> actions;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          folderProvider('/root').overrideWith((Ref ref) async => entries),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              ref.watch(folderProvider('/root'));
              actions = filesSelectionActions(ref, '/root');
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    String r(String name) => p.join('/root', name);
    final SelectionAction extract = actions.singleWhere(
      (SelectionAction a) => a.label == 'Extract',
    );
    expect(extract.isShownFor(<String>{r('A.zip'), r('B.zip')}), isTrue);
    expect(extract.isShownFor(<String>{r('A.zip'), r('notes.txt')}), isFalse);
    expect(extract.isShownFor(<String>{r('A.zip'), r('Comics')}), isFalse);
    expect(extract.isShownFor(<String>{}), isFalse);
    // The others stay whatever is selected.
    expect(
      actions
          .where((SelectionAction a) => a.label != 'Extract')
          .every((SelectionAction a) => a.isShownFor(<String>{r('notes.txt')})),
      isTrue,
    );
  });

  testWidgets(
    'Extract here puts each ZIP in a folder of its own name, numbered when taken',
    (WidgetTester tester) async {
      final String d = dir.path;
      for (final String name in <String>['Comic A.zip', 'Comic B.zip']) {
        File(p.join(d, name)).writeAsStringSync('zip');
      }
      Directory(p.join(d, 'Comic A')).createSync();
      final List<FileEntry> zips = <FileEntry>[
        _entry(d, 'Comic A.zip'),
        _entry(d, 'Comic B.zip'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => extractEntries(context, ref, zips),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Extract 2 ZIPs'), findsOneWidget);
      await tester.tap(find.text('Extract here'));
      // Real folder listing runs between the native calls.
      for (int i = 0; i < 50 && extracts.length < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 2));

      expect(
        <Object?>[
          for (final MethodCall c in extracts)
            (c.arguments as Map<Object?, Object?>)['target'],
        ],
        <String>[p.join(d, 'Comic A (2)'), p.join(d, 'Comic B')],
      );
      // The folder each comic was zipped as is not nested again.
      expect(
        <Object?>[
          for (final MethodCall c in extracts)
            (c.arguments as Map<Object?, Object?>)['strip'],
        ],
        <String>['Comic A/', 'Comic B/'],
      );
      expect(
        find.text('Extracted 2 ZIPs into ${p.basename(d)}'),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );
}
