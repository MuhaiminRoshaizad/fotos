import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/file_row.dart';
import 'package:fotos/features/files/presentation/file_tile.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/files_screen.dart';
import 'package:fotos/features/files/presentation/files_selection.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

FileEntry _entry(String name, {bool folder = false}) => FileEntry(
  path: '/root/$name',
  name: name,
  kind: kindOf(name, isDirectory: folder),
  size: 10,
  modified: DateTime(2026, 11, 9),
);

void main() {
  final List<FileEntry> entries = <FileEntry>[
    _entry('Archive', folder: true),
    _entry('Iron Orchard Vol. 01.zip'),
    _entry('Moonlit Harbor Vol. 03.zip'),
    _entry('notes.txt'),
  ];

  test('pinned entries go first, each part keeping its order', () {
    expect(
      pinnedFirst(entries, <String>{
        '/root/notes.txt',
        '/root/Moonlit Harbor Vol. 03.zip',
      }).map((FileEntry e) => e.name),
      <String>[
        'Moonlit Harbor Vol. 03.zip',
        'notes.txt',
        'Archive',
        'Iron Orchard Vol. 01.zip',
      ],
    );
    expect(pinnedFirst(entries, const <String>{}), same(entries));
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    late ProviderContainer container;
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          folderProvider('/root').overrideWith((Ref ref) async => entries),
          zipCoverProvider.overrideWith(
            (Ref ref, (String, int) zip) async => null as Uint8List?,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: const <Widget>[FolderMoreButton(dir: '/root')],
            ),
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

  testWidgets('a pinned comic sits first in its folder, marked, in the list '
      'and in the grid', (WidgetTester tester) async {
    final ProviderContainer c = await open(tester);
    await c
        .read(topPinsProvider.notifier)
        .toggle('/root/Moonlit Harbor Vol. 03.zip');
    await tester.pumpAndSettle();

    final FileRow top = tester.widget(find.byType(FileRow).first);
    expect(top.entry.name, 'Moonlit Harbor Vol. 03.zip');
    expect(top.pinned, isTrue);
    expect(find.textContaining('Pinned'), findsOneWidget);

    await chooseFromMenu(tester, 'Show as grid');
    await tester.pumpAndSettle();
    final FileTile first = tester.widget(find.byType(FileTile).first);
    expect(first.entry.name, 'Moonlit Harbor Vol. 03.zip');
    expect(first.pinned, isTrue);
    expect(
      find.bySemanticsLabel('Moonlit Harbor Vol. 03.zip, pinned'),
      findsOneWidget,
    );
  });
}

/// Opens the folder bar's ⋯ menu and taps [label] in it.
Future<void> chooseFromMenu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
}
