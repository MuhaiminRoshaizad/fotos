import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/entrance.dart';

Widget _row(int i) => SlideUpIn(index: i, child: Text('row $i'));

double _opacity(WidgetTester tester, String text) {
  // Only the row's own fade: the route's page transition has one too.
  final Finder fade = find.descendant(
    of: find.ancestor(of: find.text(text), matching: find.byType(SlideUpIn)),
    matching: find.byType(FadeTransition),
  );
  if (fade.evaluate().isEmpty) return 1;
  return tester.widget<FadeTransition>(fade.first).opacity.value;
}

void main() {
  testWidgets('rows on an opened page slide in, staggered', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EntranceScope(
          child: Column(children: <Widget>[_row(0), _row(5)]),
        ),
      ),
    );
    expect(_opacity(tester, 'row 0'), 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The first row is on its way; the sixth has not started yet.
    expect(_opacity(tester, 'row 0'), greaterThan(0));
    expect(_opacity(tester, 'row 5'), 0);
    await tester.pumpAndSettle();
    expect(_opacity(tester, 'row 5'), 1);
  });

  testWidgets('rows outside an opened page do not move', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: _row(0)));
    expect(
      find.descendant(
        of: find.byType(SlideUpIn),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('no motion when animations are switched off', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: EntranceScope(child: _row(0)),
        ),
      ),
    );
    expect(_opacity(tester, 'row 0'), 1);
  });
}
