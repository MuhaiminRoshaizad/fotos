import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/core/media/add_to_album.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';

import '../../support/fake_media_repository.dart';

class _MemoryEmptyAlbums extends EmptyAlbumsNotifier {
  @override
  Future<List<String>> build() async => <String>[];

  @override
  Future<void> add(String name) async =>
      state = AsyncData<List<String>>(<String>[name, ...?state.value]);

  @override
  Future<void> remove(String name) async => state = AsyncData<List<String>>(
    (state.value ?? <String>[]).where((String n) => n != name).toList(),
  );
}

class _NoPrefs extends AlbumPrefsNotifier {
  @override
  Future<AlbumPrefs> build() async => const AlbumPrefs();
}

void main() {
  test('placeholders disappear once a real album has that name', () {
    expect(pendingEmptyAlbums(<String>['Trip', 'Work'], const []), <String>[
      'Trip',
      'Work',
    ]);
  });

  testWidgets('New album creates an empty album without picking photos', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          emptyAlbumsProvider.overrideWith(_MemoryEmptyAlbums.new),
          albumPrefsProvider.overrideWith(_NoPrefs.new),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Albums').last);
    await tester.pumpAndSettle();

    // More offers a new album or a new gallery.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New album'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'Holiday 2026');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Straight into the empty album, no picker.
    expect(find.text('Holiday 2026 is empty'), findsOneWidget);
    expect(find.text('Add photos'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Holiday 2026'), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);
  });

  testWidgets('the Albums bar is Select and More, and More holds New and '
      'Sort', (WidgetTester tester) async {
    // A phone, so the sort sheet has a phone's height to open into.
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          emptyAlbumsProvider.overrideWith(_MemoryEmptyAlbums.new),
          albumPrefsProvider.overrideWith(_NoPrefs.new),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Albums').last);
    await tester.pumpAndSettle();

    expect(find.text('Select'), findsOneWidget);
    expect(find.byTooltip('Sort albums'), findsNothing);
    expect(find.byTooltip('New album or gallery'), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('New album'), findsOneWidget);
    expect(find.text('New gallery'), findsOneWidget);
    await tester.tap(find.text('Sort albums…'));
    await tester.pumpAndSettle();
    expect(find.text('Sort albums'), findsOneWidget);
    expect(find.text('Most recent photo'), findsOneWidget);
  });
}
