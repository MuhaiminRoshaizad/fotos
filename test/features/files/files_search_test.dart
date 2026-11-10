import 'package:flutter/cupertino.dart' show CupertinoSearchTextField;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/files_screen.dart';

FileEntry _entry(String name, {bool folder = false}) => FileEntry(
  path: '/root/$name',
  name: name,
  kind: kindOf(name, isDirectory: folder),
  size: 10,
  modified: DateTime(2026, 11, 9),
);

void main() {
  Future<void> open(WidgetTester tester, List<FileEntry> entries) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          folderProvider('/root').overrideWith((Ref ref) async => entries),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: FolderBody(
              dir: '/root',
              header: Text('Header'),
              preface: Text('Storage'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing filters the folder by name and hides the preface', (
    WidgetTester tester,
  ) async {
    await open(tester, <FileEntry>[
      _entry('Download', folder: true),
      _entry('tax-return-2025.pdf'),
      _entry('notes.txt'),
    ]);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'TAX');
    await tester.pumpAndSettle();

    expect(find.text('tax-return-2025.pdf'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
    expect(find.text('notes.txt'), findsNothing);
    expect(find.text('Storage'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
  });

  testWidgets('a search with no match says so', (WidgetTester tester) async {
    await open(tester, <FileEntry>[_entry('notes.txt')]);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Nothing in this folder matches “zzz”.'), findsOneWidget);
  });

  testWidgets('an empty folder offers no search field', (
    WidgetTester tester,
  ) async {
    await open(tester, <FileEntry>[]);

    expect(find.byType(CupertinoSearchTextField), findsNothing);
    expect(find.text('This folder is empty'), findsOneWidget);
  });
}
