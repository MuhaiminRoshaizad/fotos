import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/files_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// 26 comics for each letter but X, Y and Z: a long folder sorted by name.
final List<FileEntry> _comics = <FileEntry>[
  for (final String l in 'ABCDEFGHIJKLMNOPQRSTUVW'.split(''))
    for (int i = 1; i <= 8; i++)
      FileEntry(
        path: '/s/Comic/Source/$l comic $i.zip',
        name: '$l comic $i.zip',
        kind: FileKind.zip,
        size: 10,
        modified: DateTime(2026, 11, 9),
      ),
];

/// The folder's own list, not the search field's scrollable.
final Finder _list = find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  Future<void> open(WidgetTester tester, String dir) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRootProvider.overrideWith((Ref ref) async => '/s'),
          folderProvider(dir).overrideWith((Ref ref) async => _comics),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: FolderBody(dir: dir, header: const SizedBox(height: 100)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final Finder handle = find.byIcon(CupertinoIcons.chevron_up_chevron_down);

  testWidgets('a long folder gets the handle, and dragging it names the '
      'letter of the row it lands on', (WidgetTester tester) async {
    await open(tester, '/s/Comic/Source');
    final ScrollPosition pos = tester.state<ScrollableState>(_list).position;
    pos.jumpTo(10);
    await tester.pump();
    expect(handle, findsOneWidget);

    final TestGesture g = await tester.startGesture(tester.getCenter(handle));
    for (int i = 0; i < 25; i++) {
      await g.moveBy(const Offset(0, 12));
      await tester.pump();
    }
    await tester.pump();
    // The row under the bar now starts with the letter shown.
    final String letter = 'ABCDEFGHIJKLMNOPQRSTUVW'
        .split('')
        .firstWhere((String l) => find.text(l).evaluate().isNotEmpty);
    final Iterable<String> visible = tester
        .widgetList<Text>(find.textContaining(' comic '))
        .map((Text t) => t.data!)
        .where((String n) {
          final Rect r = tester.getRect(find.text(n));
          return r.bottom > 44 && r.top < 800;
        });
    expect(visible.first[0], letter);
    expect(letter, isNot('A'));
    await g.up();
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('the Files tab itself keeps a plain list', (
    WidgetTester tester,
  ) async {
    await open(tester, '/s');
    tester.state<ScrollableState>(_list).position.jumpTo(10);
    await tester.pump();
    expect(handle, findsNothing);
  });
}
