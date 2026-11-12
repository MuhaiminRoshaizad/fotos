import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/app/floating_nav.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';

import '../support/fake_media_repository.dart';

class _NoEmpty extends EmptyAlbumsNotifier {
  @override
  Future<List<String>> build() async => const <String>[];
}

class _NoPrefs extends AlbumPrefsNotifier {
  @override
  Future<AlbumPrefs> build() async => const AlbumPrefs();
}

void main() {
  testWidgets('the tabs show on the four main pages only, and come back on '
      'the way out of a pushed page', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          emptyAlbumsProvider.overrideWith(_NoEmpty.new),
          albumPrefsProvider.overrideWith(_NoPrefs.new),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNav), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Albums').last);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNav), findsOneWidget);

    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNav), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNav), findsOneWidget);
  });
}
