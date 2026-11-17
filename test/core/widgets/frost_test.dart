import 'package:flutter/cupertino.dart' show showCupertinoDialog;
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
                  onPressed: () => showCupertinoDialog<void>(
                    context: context,
                    builder: (_) => const SizedBox(height: 100),
                  ),
                  child: const Text('Dialog'),
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

  /// How dark the popup's scrim is, as a share of how dark it ends up.
  double dim(WidgetTester tester, double full) =>
      tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).color!.a /
      full;

  /// Frame by frame (16 ms), the blur fades exactly as the scrim darkens
  /// over it: switched in one frame, the bars went sharp under a scrim that
  /// had barely begun, which showed as a flicker.
  Future<void> expectInStep(WidgetTester tester, double full) async {
    bool partly = false;
    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(ModalBarrier).evaluate().length < 2) break;
      final double d = dim(tester, full);
      expect(popupWatch.clear, closeTo(1 - d, 0.01), reason: 'frame $i');
      if (d > 0.2 && d < 0.8) {
        partly = true;
        expect(blurring(tester), isTrue, reason: 'frame $i');
      }
    }
    expect(partly, isTrue, reason: 'it should pass through partly blurred');
  }

  for (final String popup in <String>['Sheet', 'Dialog']) {
    testWidgets(
      'a frosted bar fades its blur out under a ${popup.toLowerCase()}'
      ' and back in as it closes, with the scrim',
      (WidgetTester tester) async {
        await open(tester);
        expect(popupWatch.clear, 1);
        expect(blurring(tester), isTrue);

        await tester.tap(find.text(popup));
        await tester.pumpAndSettle();
        final double full = tester
            .widget<ModalBarrier>(find.byType(ModalBarrier).last)
            .color!
            .a;
        expect(popupWatch.clear, 0);
        expect(blurring(tester), isFalse);

        // Again from the start, now that the scrim's full darkness is known.
        Navigator.of(tester.element(find.byType(Frost))).pop();
        await tester.pumpAndSettle();
        expect(popupWatch.clear, 1);
        await tester.tap(find.text(popup));
        await tester.pump();
        await expectInStep(tester, full);
        await tester.pumpAndSettle();
        expect(blurring(tester), isFalse);

        Navigator.of(tester.element(find.byType(Frost))).pop();
        await tester.pump();
        // Still off on the frame the close starts: it comes back with the scrim.
        expect(blurring(tester), isFalse);
        await expectInStep(tester, full);
        await tester.pumpAndSettle();
        expect(popupWatch.clear, 1);
        expect(blurring(tester), isTrue);
      },
    );
  }

  testWidgets('a pushed page leaves the blur alone', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The page below still shows during the slide, blurred as before.
    expect(popupWatch.clear, 1);
    expect(blurring(tester), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('a sheet left open by a navigator that has gone does not hold '
      'the blur off', (WidgetTester tester) async {
    await open(tester);
    await tester.tap(find.text('Sheet'));
    await tester.pumpAndSettle();
    expect(popupWatch.clear, 0);

    await tester.pumpWidget(const SizedBox());
    expect(popupWatch.clear, 1);
  });
}
