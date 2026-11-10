import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/features/library/presentation/library_screen.dart';

import '../../support/fake_media_repository.dart';

Widget _app(FakeMediaRepository repo) => ProviderScope(
  retry: (_, _) => null,
  overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: buildAppTheme(Brightness.light),
    home: const LibraryScreen(kind: LibraryKind.photos),
  ),
);

void main() {
  testWidgets('denied access explains and asks, then offers settings', (
    WidgetTester tester,
  ) async {
    final FakeMediaRepository repo = FakeMediaRepository(
      accessState: MediaAccess.denied,
    );
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Let fotos show your photos'), findsOneWidget);

    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    expect(repo.settingsOpened, 1);
  });

  testWidgets('granting access on request shows the library', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        FakeMediaRepository(
          accessState: MediaAccess.denied,
          grantOnRequest: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();
    expect(find.text('No photos yet'), findsOneWidget);
  });

  testWidgets('limited access shows the banner over the grid', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(FakeMediaRepository(accessState: MediaAccess.limited)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Allow all photos'), findsOneWidget);
    expect(find.text('Pick more'), findsOneWidget);
  });

  testWidgets('a failed load shows an error with retry', (
    WidgetTester tester,
  ) async {
    final FakeMediaRepository repo = FakeMediaRepository(failLoads: true);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Couldn\'t load your photos'), findsOneWidget);

    repo.failLoads = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No photos yet'), findsOneWidget);
  });

  testWidgets('Select enters select mode; Done leaves it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        FakeMediaRepository(
          items: <AssetEntity>[fakeAsset('a'), fakeAsset('b')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 photos'), findsOneWidget);

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Select items'), findsOneWidget);
    // The bar button hugs its label instead of covering the bar's title.
    final Size selectAll = tester.getSize(
      find
          .ancestor(
            of: find.text('Select all'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(selectAll.width, lessThan(200));

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('2 selected'), findsNothing);
  });
}
