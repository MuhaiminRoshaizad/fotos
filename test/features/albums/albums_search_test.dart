import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';

import '../../support/fake_media_repository.dart';

/// Two albums with nothing in them yet: enough to search by name.
class _TwoEmptyAlbums extends EmptyAlbumsNotifier {
  @override
  Future<List<String>> build() async => <String>['Holiday 2026', 'Receipts'];
}

class _NoPrefs extends AlbumPrefsNotifier {
  @override
  Future<AlbumPrefs> build() async => const AlbumPrefs();
}

void main() {
  testWidgets('typing in Albums filters albums by name and hides the rest of '
      'the page', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          emptyAlbumsProvider.overrideWith(_TwoEmptyAlbums.new),
          albumPrefsProvider.overrideWith(_NoPrefs.new),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Albums').last);
    await tester.pumpAndSettle();
    expect(find.text('Holiday 2026'), findsOneWidget);
    expect(find.text('Receipts'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'HOLI');
    await tester.pumpAndSettle();
    expect(find.text('Holiday 2026'), findsOneWidget);
    expect(find.text('Receipts'), findsNothing);
    // Favourites, Recently deleted and Takeout are not albums to search.
    expect(find.text('Favourites'), findsNothing);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No album is called “zzz”.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
  });
}
