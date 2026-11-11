import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/files_screen.dart';

FileEntry _entry(String name) => FileEntry(
  path: '/root/$name',
  name: name,
  kind: kindOf(name, isDirectory: false),
  size: 10,
  modified: DateTime(2026, 11, 9),
);

/// The folder's contents, changed by the test as a move or delete would.
class _Contents extends Notifier<List<FileEntry>> {
  @override
  List<FileEntry> build() => <FileEntry>[
    _entry('a.pdf'),
    _entry('b.pdf'),
    _entry('c.pdf'),
  ];

  /// Changes the folder, then tells the list to read it again, as the
  /// app does after a move or a delete.
  void set(List<FileEntry> next) {
    state = next;
    ref.invalidate(folderProvider('/root'));
  }
}

final _contents = NotifierProvider<_Contents, List<FileEntry>>(_Contents.new);

void main() {
  Future<ProviderContainer> open(WidgetTester tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          folderProvider(
            '/root',
          ).overrideWith((Ref ref) async => ref.read(_contents)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                container = ProviderScope.containerOf(context);
                return const FolderBody(
                  dir: '/root',
                  header: SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a row that has gone closes up instead of vanishing', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = await open(tester);
    final double full = tester.getSize(find.text('b.pdf')).height;
    final double cBefore = tester.getTopLeft(find.text('c.pdf')).dy;

    c.read(_contents.notifier).set(<FileEntry>[
      _entry('a.pdf'),
      _entry('c.pdf'),
    ]);
    await tester.pump();
    await tester.pump();
    // Still there, on its way out, and the row below has not jumped yet.
    expect(find.text('b.pdf'), findsOneWidget);
    expect(tester.getSize(find.text('b.pdf')).height, full);
    expect(tester.getTopLeft(find.text('c.pdf')).dy, cBefore);

    await tester.pump(const Duration(milliseconds: 130));
    final double mid = tester.getTopLeft(find.text('c.pdf')).dy;
    expect(mid, lessThan(cBefore));

    await tester.pumpAndSettle();
    expect(find.text('b.pdf'), findsNothing);
    expect(tester.getTopLeft(find.text('c.pdf')).dy, lessThan(mid));
  });

  testWidgets('a row that has arrived opens out', (WidgetTester tester) async {
    final ProviderContainer c = await open(tester);
    c.read(_contents.notifier).set(<FileEntry>[
      _entry('a.pdf'),
      _entry('b.pdf'),
      _entry('c.pdf'),
      _entry('d.pdf'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('d.pdf'), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('d.pdf'), findsOneWidget);
  });

  testWidgets('typing in the search field filters at once, without motion', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(EditableText), 'a.');
    await tester.pump();
    expect(find.text('b.pdf'), findsNothing);
    await tester.pumpAndSettle();
  });
}
