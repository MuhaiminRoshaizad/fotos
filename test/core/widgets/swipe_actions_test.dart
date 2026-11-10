import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/core/widgets/swipe_actions.dart';

void main() {
  testWidgets('swiping left reveals the actions; a tap on one runs it', (
    WidgetTester tester,
  ) async {
    int deleted = 0, opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: SwipeActions(
            actions: <SwipeAction>[
              SwipeAction(icon: Icons.more_horiz, label: 'More', onTap: () {}),
              SwipeAction(
                icon: Icons.delete,
                label: 'Delete',
                destructive: true,
                onTap: () => deleted++,
              ),
            ],
            child: Material(
              color: Colors.white,
              child: InkWell(
                onTap: () => opened++,
                child: const SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: Text('notes.txt'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Closed: the row covers the buttons, so a tap opens the file.
    await tester.tap(find.text('notes.txt'));
    expect(opened, 1);

    await tester.fling(find.text('notes.txt'), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, 1);

    // Open again, then a tap on the row only closes it.
    await tester.fling(find.text('notes.txt'), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.tap(find.text('notes.txt'));
    expect(opened, 2);
  });
}
