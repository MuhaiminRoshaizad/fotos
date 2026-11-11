import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/hold_to_move_cursor.dart';

void main() {
  testWidgets('holding in a field moves the cursor instead of selecting a '
      'word, and it follows the finger', (WidgetTester tester) async {
    final TextEditingController c = TextEditingController(
      text: 'Moonlit Harbor Chronicles',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 320,
            child: HoldToMoveCursor(child: CupertinoTextField(controller: c)),
          ),
        ),
      ),
    );
    final Rect field = tester.getRect(find.byType(EditableText));
    // Inside "Harbor": a hold here on Android would select the word.
    final TestGesture g = await tester.startGesture(
      Offset(field.left + 90, field.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.selection.isCollapsed, isTrue);
    final int first = c.selection.baseOffset;
    expect(first, greaterThan(0));

    await g.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(c.selection.isCollapsed, isTrue);
    expect(c.selection.baseOffset, greaterThan(first));

    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.selection.isCollapsed, isTrue);
  });
}
