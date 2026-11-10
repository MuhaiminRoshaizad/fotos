import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/toast.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    void Function(BuildContext) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => show(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('a toast shows at the top and leaves by itself', (
    WidgetTester tester,
  ) async {
    await open(tester, (BuildContext c) => showToast(c, 'Cover changed'));

    expect(find.text('Cover changed'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Cover changed')).dy,
      lessThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio / 4,
      ),
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Cover changed'), findsNothing);
  });

  testWidgets('a new toast replaces the one showing', (
    WidgetTester tester,
  ) async {
    int n = 0;
    await open(tester, (BuildContext c) => showToast(c, 'Toast ${++n}'));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Toast 1'), findsNothing);
    expect(find.text('Toast 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('the action runs and closes the toast', (
    WidgetTester tester,
  ) async {
    bool undone = false;
    await open(
      tester,
      (BuildContext c) => showToast(
        c,
        'Moved to Recently deleted',
        actionLabel: 'Undo',
        onAction: () => undone = true,
      ),
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(undone, isTrue);
    expect(find.text('Moved to Recently deleted'), findsNothing);
  });
}
