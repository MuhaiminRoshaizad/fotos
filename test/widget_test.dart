import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/core/media/media_providers.dart';

import 'support/fake_media_repository.dart';

void main() {
  testWidgets('the floating nav switches between the four tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();

    for (final String tab in <String>['Photos', 'Videos', 'Albums', 'Files']) {
      expect(find.bySemanticsLabel(tab), findsWidgets);
    }
    expect(find.text('No photos yet'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Albums').last);
    await tester.pumpAndSettle();
    expect(find.text('On this phone'), findsOneWidget);
  });
}
