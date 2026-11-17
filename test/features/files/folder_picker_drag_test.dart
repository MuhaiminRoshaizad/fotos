import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/folder_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// The Move to picker on a Pixel-sized screen, with the app's rubber-band
/// scrolling and 30 folders to scroll through.
Future<void> openPicker(WidgetTester tester) async {
  tester.view.physicalSize = const Size(960, 2142);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final Directory root = Directory.systemTemp.createTempSync('picker');
  addTearDown(() => root.deleteSync(recursive: true));
  final ProviderContainer container = ProviderContainer(
    overrides: [
      folderProvider.overrideWith(
        (Ref ref, String path) async => <FileEntry>[
          for (int i = 0; i < 30; i++)
            FileEntry(
              path: p.join(path, 'Folder $i'),
              name: 'Folder $i',
              kind: FileKind.folder,
              size: 0,
              modified: DateTime(2026),
            ),
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => TextButton(
            onPressed: () => pickFolder(
              context,
              ref,
              start: root.path,
              root: root.path,
              action: 'Move here',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  double top(WidgetTester tester) =>
      tester.getTopLeft(find.byType(DraggableScrollableSheet)).dy;

  // In logical pixels: the phone's swipes divided by its 2.625 density.
  Future<void> expand(WidgetTester tester) async {
    await tester.timedDragFrom(
      const Offset(183, 650),
      const Offset(0, -420),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a quick flick down stops the list at its top, sheet in place', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);
    await expand(tester);
    final double expanded = top(tester);

    await tester.timedDragFrom(
      const Offset(183, 305),
      const Offset(0, 190),
      const Duration(milliseconds: 90),
    );
    // Every frame after the finger lifts: the sheet never moves.
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(top(tester), expanded, reason: 'frame $i');
    }
  });

  testWidgets('a slow pull down settles at the opening height', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);
    final double opened = top(tester);
    await expand(tester);
    // Back to the list's top first, then pull the sheet itself.
    await tester.timedDragFrom(
      const Offset(183, 305),
      const Offset(0, 190),
      const Duration(milliseconds: 90),
    );
    await tester.pumpAndSettle();
    await tester.timedDragFrom(
      const Offset(183, 305),
      const Offset(0, 115),
      const Duration(milliseconds: 900),
    );
    await tester.pumpAndSettle();
    expect(top(tester), moreOrLessEquals(opened, epsilon: 1));
  });
}
