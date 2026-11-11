import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/selection/selection.dart';
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
    _entry('Comics', folder: true),
    for (int i = 1; i <= 7; i++) _entry('chapter-$i.zip'),
  ];

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    late ProviderContainer container;
    // A phone, not the test rig's 800-wide default.
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          folderProvider('/root').overrideWith((Ref ref) async => entries),
          // No archive to read in a test: every ZIP keeps its glyph.
          zipCoverProvider.overrideWith(
            (Ref ref, (String, int) zip) async => null as Uint8List?,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const <Widget>[FilesViewButton()]),
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

  testWidgets('the view button switches rows for a grid, and back', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(find.byType(FileRow), findsNWidgets(8));
    expect(find.byType(FileTile), findsNothing);

    await tester.tap(find.byTooltip('Show as grid'));
    await tester.pumpAndSettle();
    expect(find.byType(FileRow), findsNothing);
    expect(find.byType(FileTile), findsWidgets);
    // Three across on a phone-width page.
    final double first = tester.getTopLeft(find.byType(FileTile).at(0)).dy;
    expect(tester.getTopLeft(find.byType(FileTile).at(2)).dy, first);
    expect(
      tester.getTopLeft(find.byType(FileTile).at(3)).dy,
      greaterThan(first),
    );

    await tester.tap(find.byTooltip('Show as list'));
    await tester.pumpAndSettle();
    expect(find.byType(FileRow), findsNWidgets(8));
  });

  testWidgets('the choice is still there the next time the app starts', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = await open(tester);
    await tester.tap(find.byTooltip('Show as grid'));
    await tester.pumpAndSettle();
    expect(c.read(filesGridProvider).value, isTrue);

    final ProviderContainer next = ProviderContainer();
    addTearDown(next.dispose);
    expect(await next.read(filesGridProvider.future), isTrue);
  });

  testWidgets('in the grid, holding a tile selects it and taps then toggle', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = await open(tester);
    await tester.tap(find.byTooltip('Show as grid'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('chapter-1.zip'));
    await tester.pumpAndSettle();
    expect(c.read(selectionProvider).ids, <String>{'/root/chapter-1.zip'});
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);

    await tester.tap(find.text('chapter-2.zip'));
    await tester.pumpAndSettle();
    expect(c.read(selectionProvider).ids, hasLength(2));
  });

  testWidgets('tiles keep their shape at a large text size', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);
    await tester.tap(find.byTooltip('Show as grid'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
