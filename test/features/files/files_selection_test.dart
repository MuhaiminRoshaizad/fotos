import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/selection/selection.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/file_actions.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/files_screen.dart';
import 'package:fotos/features/files/presentation/files_selection.dart';

FileEntry _entry(String name, {bool folder = false}) => FileEntry(
  path: '/root/$name',
  name: name,
  kind: kindOf(name, isDirectory: folder),
  size: 10,
  modified: DateTime(2026, 11, 9),
);

void main() {
  final List<FileEntry> entries = <FileEntry>[
    _entry('Receipts', folder: true),
    _entry('a.pdf'),
    _entry('b.pdf'),
    _entry('c.csv'),
  ];

  setUp(() {
    // Starting a selection and each swept row vibrate.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          folderProvider('/root').overrideWith((Ref ref) async => entries),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              container = ProviderScope.containerOf(context);
              final FolderBar bar = folderBar(ref, '/root');
              return Scaffold(
                appBar: AppBar(
                  title: Text(bar.barTitle ?? 'Files'),
                  leading: bar.leading,
                  actions: bar.trailing,
                ),
                body: const FolderBody(dir: '/root', header: SizedBox.shrink()),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Set<String> picked(ProviderContainer c) => c.read(selectionProvider).ids;

  testWidgets('holding a row starts selecting from it, and taps then toggle', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = await open(tester);
    expect(c.read(selectionProvider).active, isFalse);

    await tester.longPress(find.text('a.pdf'));
    await tester.pumpAndSettle();
    expect(c.read(selectionProvider).owner, filesSelectionOwner('/root'));
    expect(picked(c), <String>{'/root/a.pdf'});
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('b.pdf'));
    await tester.tap(find.text('Receipts'));
    await tester.pumpAndSettle();
    expect(picked(c), <String>{'/root/a.pdf', '/root/b.pdf', '/root/Receipts'});

    await tester.tap(find.text('a.pdf'));
    await tester.pumpAndSettle();
    expect(picked(c), <String>{'/root/b.pdf', '/root/Receipts'});
  });

  testWidgets('Select, Select all, Deselect all and Done', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = await open(tester);

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Select items'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.circle), findsNWidgets(4));

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(picked(c), hasLength(4));
    expect(find.text('4 selected'), findsOneWidget);

    await tester.tap(find.text('Deselect all'));
    await tester.pumpAndSettle();
    expect(picked(c), isEmpty);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(c.read(selectionProvider).active, isFalse);
    expect(find.byIcon(CupertinoIcons.circle), findsNothing);
  });

  testWidgets('a drag begun on a tick sweeps the rows it passes', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = await open(tester);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    final Offset from = tester.getCenter(
      find.byIcon(CupertinoIcons.circle).at(1),
    );
    final Offset to = tester.getCenter(find.text('c.csv'));
    final TestGesture g = await tester.startGesture(from);
    await g.moveBy(const Offset(0, 30));
    await g.moveTo(Offset(from.dx, to.dy));
    await g.up();
    await tester.pumpAndSettle();

    expect(picked(c), <String>{'/root/a.pdf', '/root/b.pdf', '/root/c.csv'});
  });

  test('one entry is named, several are counted', () {
    expect(describeEntries(<FileEntry>[entries[1]]), 'a.pdf');
    expect(describeEntries(entries), '4 items');
  });
}
