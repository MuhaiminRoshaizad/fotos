import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/file_actions.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

FileEntry _folder(String path) => FileEntry(
  path: path,
  name: path.split('/').last,
  kind: FileKind.folder,
  size: 0,
  modified: DateTime(2026, 11, 12),
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> menuFor(WidgetTester tester, String path) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRootProvider.overrideWith((Ref ref) async => '/root'),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              ref.watch(storageRootProvider);
              return Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showEntryActions(context, ref, _folder(path)),
                  child: const Text('More'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
  }

  testWidgets('a folder on the Files tab has one Pin, to its Pinned section', (
    WidgetTester tester,
  ) async {
    await menuFor(tester, '/root/Comic');
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Pin to top'), findsNothing);
    expect(find.text('Add to Files tab'), findsNothing);
  });

  testWidgets('a folder inside another keeps Pin to top and Add to Files tab', (
    WidgetTester tester,
  ) async {
    await menuFor(tester, '/root/Comic/Album');
    expect(find.text('Pin to top'), findsOneWidget);
    expect(find.text('Add to Files tab'), findsOneWidget);
    expect(find.text('Pin'), findsNothing);
  });
}
