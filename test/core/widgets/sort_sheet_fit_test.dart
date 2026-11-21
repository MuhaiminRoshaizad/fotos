import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/sort_sheet.dart';

/// Android 14+ grows small text by the full factor and damps large text.
class _DampedScaler extends TextScaler {
  const _DampedScaler(this.factor);
  final double factor;

  @override
  double scale(double fontSize) =>
      fontSize * (fontSize <= 14 ? factor : 1 + (factor - 1) * 14 / fontSize);

  @override
  double get textScaleFactor => factor;
}

/// The album Sort sheet, its fullest form: three orders, the directions,
/// Favourites first and Use for all albums, then Apply.
Future<void> _open(WidgetTester tester, {double text = 1}) async {
  // A Pixel 9 Pro: 412 x 915 dp, with the 48 dp three-button bar (the
  // gesture bar is smaller, so this is the harder case).
  tester.view.physicalSize = const Size(412, 915) * 2.625;
  tester.view.devicePixelRatio = 2.625;
  tester.view.padding = const FakeViewPadding(bottom: 48 * 2.625);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: _DampedScaler(text)),
        child: child!,
      ),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => pickSort(
                context,
                title: 'Sort',
                labels: const <String>['Date taken', 'Name', 'Length'],
                directions: const <(String, String)>[
                  ('Newest first', 'Oldest first'),
                  ('A to Z', 'Z to A'),
                  ('Longest first', 'Shortest first'),
                ],
                by: 0,
                reversed: false,
                option: const SortOption(
                  'Favourites first',
                  footer: 'Favourites sit at the top, like a pinned album.',
                  value: true,
                ),
                forAllLabel: 'Use for all albums',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the whole Sort sheet, Apply included, sits above the '
      'navigation bar', (WidgetTester tester) async {
    await _open(tester);
    final Rect apply = tester.getRect(find.text('Apply'));
    expect(apply.bottom, lessThanOrEqualTo(915 - 48));
    expect(tester.getRect(find.text('Sort')).top, greaterThanOrEqualTo(0));
  });

  testWidgets('at 200% text the sheet scrolls to Apply instead of cutting '
      'it off', (WidgetTester tester) async {
    await _open(tester, text: 2);
    await tester.scrollUntilVisible(
      find.text('Apply'),
      100,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    final Rect apply = tester.getRect(find.text('Apply'));
    expect(apply.bottom, lessThanOrEqualTo(915 - 48));
  });
}
