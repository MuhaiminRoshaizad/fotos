import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/core/widgets/sort_sheet.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('Use for all albums sorts every album without its own order, new '
      'ones included, and survives a restart', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    const AlbumSort byName = AlbumSort(AlbumSortBy.name);
    const AlbumSort longest = AlbumSort(AlbumSortBy.length);
    final ProviderContainer c = ProviderContainer();
    await c.read(albumPrefsProvider.future);
    final AlbumPrefsNotifier prefs = c.read(albumPrefsProvider.notifier);
    await prefs.setSort('camera', longest);
    await prefs.setSort('comic-1', longest);

    await prefs.setSortForAll('comic-1', byName);

    AlbumPrefs p = c.read(albumPrefsProvider).value!;
    // A comic extracted later has no sort of its own: it reads by name.
    expect(p.sortFor('comic-2').by, AlbumSortBy.name);
    // The album it was set from now follows the default too.
    expect(p.sortFor('comic-1').by, AlbumSortBy.name);
    // An album given its own order keeps it.
    expect(p.sortFor('camera').by, AlbumSortBy.length);
    c.dispose();

    final ProviderContainer again = ProviderContainer();
    addTearDown(again.dispose);
    p = await again.read(albumPrefsProvider.future);
    expect(p.sortFor('comic-3').by, AlbumSortBy.name);
  });

  testWidgets('the sort sheet reports the Use for all switch', (
    WidgetTester tester,
  ) async {
    // A phone, so the whole sheet with its Apply button is on screen.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Builder(
          builder: (BuildContext c) {
            ctx = c;
            return const Scaffold();
          },
        ),
      ),
    );
    final Future<SortPick?> pick = pickSort(
      ctx,
      title: 'Sort',
      labels: const <String>['Date taken', 'Name'],
      directions: const <(String, String)>[
        ('Newest first', 'Oldest first'),
        ('A to Z', 'Z to A'),
      ],
      by: 0,
      reversed: false,
      forAllLabel: 'Use for all albums',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name'));
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(find.textContaining('New ones'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final SortPick? p = await pick;
    expect(p!.by, 1);
    expect(p.forAll, isTrue);
  });
}
