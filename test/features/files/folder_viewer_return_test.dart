import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/file_media_viewer.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/files_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  final List<FileEntry> pages = <FileEntry>[
    for (int i = 1; i <= 120; i++)
      FileEntry(
        path: '/root/p${'$i'.padLeft(3, '0')}.jpg',
        name: 'p${'$i'.padLeft(3, '0')}.jpg',
        kind: FileKind.image,
        size: 10,
        modified: DateTime(2026, 11, 9),
      ),
  ];

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  /// The row of [name] fully inside the 400 x 860 screen.
  bool onScreen(WidgetTester tester, String name) {
    final Finder row = find.text(name);
    if (row.evaluate().isEmpty) return false;
    final Rect r = tester.getRect(row);
    return r.top >= 0 && r.bottom <= 860;
  }

  testWidgets('closing the Files viewer after paging on lands on the last '
      'page seen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: FolderBody(dir: '/root', header: SizedBox.shrink()),
          ),
        ),
        GoRoute(
          path: '/files/media',
          builder: (_, GoRouterState state) {
            final (
              List<FileEntry> items,
              int index,
              ValueChanged<FileEntry>? onShow,
            ) = state.extra! as FileMediaArgs;
            return FileMediaViewer(items: items, index: index, onShow: onShow);
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          folderProvider('/root').overrideWith((Ref ref) async => pages),
          storageRootProvider.overrideWith((Ref ref) async => '/'),
          // No pictures to read in a test.
          fileThumbProvider.overrideWith(
            (Ref ref, (String, int) key) async => null,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final ScrollPosition folder = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;

    await tester.tap(find.text('p003.jpg'));
    await tester.pumpAndSettle();
    expect(find.byType(FileMediaViewer), findsOneWidget);

    // Forty pages on: far below the folder's first screen.
    for (int i = 0; i < 40; i++) {
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
    }
    expect(find.text('p043.jpg'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(folder.pixels, greaterThan(0));
    expect(onScreen(tester, 'p043.jpg'), isTrue);
    expect(onScreen(tester, 'p003.jpg'), isFalse);
  });
}
