import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/takeout_import/data/takeout_repository.dart';
import 'package:fotos/features/takeout_import/domain/takeout_models.dart';
import 'package:fotos/features/takeout_import/presentation/review_screen.dart';

void main() {
  testWidgets('a card with a phone copy has its final shape before the copy '
      'has been looked up', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewsProvider.overrideWith(
            (Ref ref) async => const <ReviewItem>[
              ReviewItem(
                id: 'a',
                path: '/staged/a.mp4',
                name: 'a.mp4',
                video: true,
                size: 10,
                reason: ReviewReason.name,
                phoneId: '42',
              ),
            ],
          ),
        ],
        // Pushed over a first page: the back button needs somewhere to go.
        child: MaterialApp(
          initialRoute: '/review',
          routes: <String, WidgetBuilder>{
            '/': (_) => const SizedBox(),
            '/review': (_) => const ReviewScreen(),
          },
        ),
      ),
    );
    // The list has arrived; the phone copy's lookup has not.
    await tester.pump();
    await tester.pump();

    // Two columns and the three paired choices from the first frame. A
    // card that reshaped itself when the lookup landed changed the list's
    // length under the scroll position.
    final double screen = tester.getSize(find.byType(MaterialApp)).width;
    expect(find.text('On the phone'), findsOneWidget);
    expect(
      tester.getSize(find.text('From Takeout')).width,
      lessThan(screen / 2),
    );
    expect(find.text('Keep both'), findsOneWidget);
    expect(find.text('Import it'), findsNothing);

    final double before = tester.getSize(find.byType(Card)).height;
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Card)).height, before);
  });
}
