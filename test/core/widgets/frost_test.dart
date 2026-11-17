import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/frost.dart';

void main() {
  bool blurring(WidgetTester tester) => tester
      .widget<BackdropFilter>(
        find.descendant(
          of: find.byType(Frost),
          matching: find.byType(BackdropFilter),
        ),
      )
      .enabled;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[popupWatch],
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Column(
              children: <Widget>[
                const Frost(sigma: 20, child: SizedBox(height: 44)),
                TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SizedBox(height: 200),
                  ),
                  child: const Text('Sheet'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('Page')),
                    ),
                  ),
                  child: const Text('Page'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a frosted bar stops blurring while a sheet is open', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(blurring(tester), isTrue);

    await tester.tap(find.text('Sheet'));
    await tester.pumpAndSettle();
    expect(blurring(tester), isFalse);

    // Back as soon as the sheet starts to close, not once it has gone.
    Navigator.of(tester.element(find.byType(Frost))).pop();
    await tester.pump();
    expect(blurring(tester), isTrue);
    await tester.pumpAndSettle();
    expect(blurring(tester), isTrue);
  });

  testWidgets('a pushed page leaves the blur alone', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The page below still shows during the slide, blurred as before.
    expect(blurring(tester), isTrue);
    await tester.pumpAndSettle();
  });
}
