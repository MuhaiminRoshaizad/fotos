import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/tap_outside_closes_keyboard.dart';

void main() {
  testWidgets('a tap outside a field takes the focus off it, so the keyboard '
      'closes', (WidgetTester tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: TapOutsideClosesKeyboard(
          child: Column(
            children: <Widget>[
              SizedBox(height: 100),
              CupertinoTextField(placeholder: 'Search albums'),
              SizedBox(height: 400, width: 300, child: Text('Albums')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pump();
    final EditableText field = tester.widget(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Albums'));
    await tester.pump();
    expect(field.focusNode.hasFocus, isFalse);
  });
}
