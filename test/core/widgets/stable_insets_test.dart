import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/stable_insets.dart';

void main() {
  late EdgeInsets seen;

  Widget host({
    required double top,
    required double bottom,
    double keyboard = 0,
    Size size = const Size(400, 800),
  }) => MediaQuery(
    data: MediaQueryData(
      size: size,
      padding: EdgeInsets.only(top: top, bottom: keyboard > 0 ? 0 : bottom),
      viewPadding: EdgeInsets.only(top: top, bottom: bottom),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: StableInsets(
      child: Builder(
        builder: (BuildContext context) {
          seen = MediaQuery.paddingOf(context);
          return const SizedBox();
        },
      ),
    ),
  );

  testWidgets('insets stay put while the system bars are hidden', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(top: 50, bottom: 24));
    expect(seen, const EdgeInsets.only(top: 50, bottom: 24));

    // The viewer hides the bars: Android reports nothing.
    await tester.pumpWidget(host(top: 0, bottom: 0));
    expect(seen, const EdgeInsets.only(top: 50, bottom: 24));

    await tester.pumpWidget(host(top: 50, bottom: 24));
    expect(seen, const EdgeInsets.only(top: 50, bottom: 24));
  });

  testWidgets('the keyboard still takes the bottom inset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(top: 50, bottom: 24));
    await tester.pumpWidget(host(top: 50, bottom: 24, keyboard: 300));
    expect(seen.bottom, 0);
  });

  testWidgets('a rotation starts again from what the system reports', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(top: 50, bottom: 24));
    await tester.pumpWidget(
      host(top: 20, bottom: 0, size: const Size(800, 400)),
    );
    expect(seen, const EdgeInsets.only(top: 20));
  });
}
