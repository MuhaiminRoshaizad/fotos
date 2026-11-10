import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/theme/app_theme.dart';

void main() {
  for (final Brightness b in Brightness.values) {
    test('$b theme uses Inter, no ripple and iOS page slides', () {
      final ThemeData t = buildAppTheme(b);
      expect(t.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(t.splashFactory, NoSplash.splashFactory);
      expect(
        t.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<CupertinoPageTransitionsBuilder>(),
      );
    });
  }

  testWidgets('scrolling bounces and draws no overscroll stretch', (
    WidgetTester tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    );
    const AppScrollBehavior behavior = AppScrollBehavior();
    expect(behavior.getScrollPhysics(ctx), isA<BouncingScrollPhysics>());
    const Widget child = SizedBox();
    expect(
      behavior.buildOverscrollIndicator(
        ctx,
        child,
        ScrollableDetails.vertical(controller: ScrollController()),
      ),
      same(child),
    );
  });
}
