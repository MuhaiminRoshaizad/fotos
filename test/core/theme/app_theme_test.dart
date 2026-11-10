import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoPageTransitionsBuilder;
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

  testWidgets('pushed pages show the iOS back chevron', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Builder(
          builder: (BuildContext c) => TextButton(
            onPressed: () => Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    Scaffold(appBar: AppBar(title: const Text('x'))),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.chevron_back), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

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
