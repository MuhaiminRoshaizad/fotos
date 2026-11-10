import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/lift_menu.dart';

void main() {
  setUp(() {
    // The menu opens with a long-press vibration.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  Future<List<String?>> open(WidgetTester tester) async {
    final List<String?> results = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => results.add(
                await showLiftMenu<String>(
                  context,
                  from: const Rect.fromLTWH(10, 100, 120, 120),
                  aspectRatio: 4 / 3,
                  preview: const ColoredBox(
                    key: Key('preview'),
                    color: Colors.teal,
                  ),
                  actions: const <LiftAction<String>>[
                    LiftAction<String>(
                      'share',
                      'Share',
                      CupertinoIcons.square_arrow_up,
                    ),
                    LiftAction<String>(
                      'delete',
                      'Delete',
                      CupertinoIcons.trash,
                      destructive: true,
                    ),
                  ],
                ),
              ),
              child: const Text('hold'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('hold'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('the preview settles at its own shape with the menu under it', (
    WidgetTester tester,
  ) async {
    await open(tester);

    final Rect preview = tester.getRect(find.byKey(const Key('preview')));
    expect(preview.width / preview.height, closeTo(4 / 3, 0.01));
    expect(preview.width, greaterThan(120));
    expect(
      tester.getTopLeft(find.text('Share')).dy,
      greaterThan(preview.bottom),
    );
    expect(
      tester.getBottomLeft(find.text('Delete')).dy,
      lessThan(tester.getSize(find.byType(MaterialApp)).height),
    );
  });

  testWidgets('choosing a row returns its value', (WidgetTester tester) async {
    final List<String?> results = await open(tester);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(results, <String?>['delete']);
    expect(find.text('Share'), findsNothing);
  });

  testWidgets('a tap outside dismisses with nothing chosen', (
    WidgetTester tester,
  ) async {
    final List<String?> results = await open(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(results, <String?>[null]);
    expect(find.text('Share'), findsNothing);
  });
}
