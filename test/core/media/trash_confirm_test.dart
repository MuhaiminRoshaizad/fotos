import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_actions.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/platform/native_channel.dart';
import 'package:fotos/features/albums/presentation/albums_providers.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../support/fake_media_repository.dart';

/// Records what was sent to the trash.
class _Repo extends FakeMediaRepository {
  final List<String> trashed = <String>[];

  @override
  Future<List<String>> moveToTrash(List<AssetEntity> items) async {
    trashed.addAll(items.map((AssetEntity e) => e.id));
    return items.map((AssetEntity e) => e.id).toList();
  }
}

class _Native extends NativeChannel {
  const _Native(this.allFiles);
  final bool allFiles;

  @override
  Future<bool> hasAllFilesAccess() async => allFiles;
}

final AssetEntity _photo = AssetEntity(
  id: '1',
  typeInt: 1,
  width: 1,
  height: 1,
);

void main() {
  late _Repo repo;

  Future<void> open(WidgetTester tester, {required bool allFiles}) async {
    repo = _Repo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(repo),
          nativeChannelProvider.overrideWithValue(_Native(allFiles)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) => TextButton(
                onPressed: () => ref.read(mediaActionsProvider).trash(
                  context,
                  <AssetEntity>[_photo],
                ),
                child: const Text('trash'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('trash'));
    await tester.pumpAndSettle();
  }

  /// Lets the toast's timer run out before the test's timer check.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  testWidgets('with All files access, fotos asks, and Cancel deletes nothing', (
    WidgetTester tester,
  ) async {
    await open(tester, allFiles: true);
    expect(find.text('Delete 1 item?'), findsOneWidget);
    expect(repo.trashed, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.trashed, isEmpty);
  });

  testWidgets('confirming moves the item to the trash', (
    WidgetTester tester,
  ) async {
    await open(tester, allFiles: true);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repo.trashed, <String>['1']);
    await finish(tester);
  });

  testWidgets('without it, the question is left to Android', (
    WidgetTester tester,
  ) async {
    await open(tester, allFiles: false);
    expect(find.text('Delete 1 item?'), findsNothing);
    expect(repo.trashed, <String>['1']);
    await finish(tester);
  });
}
