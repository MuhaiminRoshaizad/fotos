import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/motion.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('a Pressable reports its tap without waiting for the motion', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      _host(
        Pressable(
          label: 'Loop off',
          onTap: () => taps++,
          child: const Icon(CupertinoIcons.repeat),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(Pressable)).width,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byType(Pressable));
    // No pump in between: the tap must not depend on the press animation.
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loop off'), findsOneWidget);
  });

  testWidgets('a Pressable switched off fades to dim rather than jumping', (
    WidgetTester tester,
  ) async {
    Widget button({required bool on}) => _host(
      Pressable(
        label: 'Save',
        onTap: on ? () {} : null,
        child: const Text('Save'),
      ),
    );
    double opacity() => tester
        .widget<Opacity>(
          find.descendant(
            of: find.byType(Pressable),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;
    await tester.pumpWidget(button(on: true));
    expect(opacity(), 1);
    await tester.pumpWidget(button(on: false));
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(), allOf(lessThan(1), greaterThan(0.35)));
    await tester.pumpAndSettle();
    expect(opacity(), closeTo(0.35, 0.001));
  });

  testWidgets('a disabled Pressable does nothing', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const Pressable(
          label: 'Share',
          onTap: null,
          child: Icon(CupertinoIcons.square_arrow_up),
        ),
      ),
    );
    await tester.tap(find.byType(Pressable));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Loop glyph is dim while off and bright while on, with one '
      'glyph for both', (WidgetTester tester) async {
    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

    await tester.pumpWidget(
      _host(const TurnOnGlyph(icon: CupertinoIcons.repeat, on: false)),
    );
    expect(opacity(), lessThan(0.5));
    expect(find.byIcon(CupertinoIcons.repeat), findsOneWidget);

    await tester.pumpWidget(
      _host(const TurnOnGlyph(icon: CupertinoIcons.repeat, on: true)),
    );
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(find.byIcon(CupertinoIcons.repeat), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.repeat_1), findsNothing);
    // It turned once as it came on.
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      1,
    );
  });

  testWidgets('GlyphSwap ends on the new glyph alone', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const GlyphSwap(icon: CupertinoIcons.play_fill)),
    );
    await tester.pumpWidget(
      _host(const GlyphSwap(icon: CupertinoIcons.pause_fill)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-swap both are on screen, one leaving and one arriving.
    expect(find.byType(Icon), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.play_fill), findsNothing);
  });

  testWidgets('with animations removed, states change without travelling', (
    WidgetTester tester,
  ) async {
    Widget still(bool on) => MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _host(TurnOnGlyph(icon: CupertinoIcons.repeat, on: on)),
    );
    await tester.pumpWidget(still(false));
    await tester.pumpWidget(still(true));
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration,
      Duration.zero,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });
}
