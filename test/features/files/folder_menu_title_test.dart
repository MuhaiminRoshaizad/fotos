import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/file_actions.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> menuFor(WidgetTester tester, String dir) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Android's storage root really is named "0".
          storageRootProvider.overrideWith(
            (Ref ref) async => '/storage/emulated/0',
          ),
          folderProvider(
            dir,
          ).overrideWith((Ref ref) async => const <FileEntry>[]),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              ref.watch(storageRootProvider);
              return Scaffold(
                body: TextButton(
                  onPressed: () => showFolderMenu(context, ref, dir),
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

  testWidgets('the Files tab menu is titled Files, not "0"', (
    WidgetTester tester,
  ) async {
    await menuFor(tester, '/storage/emulated/0');
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('a folder menu is titled with the folder name', (
    WidgetTester tester,
  ) async {
    await menuFor(tester, '/storage/emulated/0/Comic');
    expect(find.text('Comic'), findsOneWidget);
  });
}
