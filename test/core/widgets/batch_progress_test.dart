import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/batch_progress.dart';

void main() {
  setUp(() {
    // The dialog buzzes when it finishes.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  Future<Future<int>> start(
    WidgetTester tester, {
    required List<String> items,
    required Future<void> Function(String) each,
    Stream<(int, int)>? progress,
  }) async {
    late Future<int> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => result = runBatch<String>(
                context,
                verb: 'Moving',
                doneVerb: 'Moved',
                what: '${items.length} items',
                items: items,
                nameOf: (String s) => s,
                each: each,
                progress: progress,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    return result;
  }

  testWidgets('counts through the items, then ends on a tick and closes', (
    WidgetTester tester,
  ) async {
    final List<Completer<void>> gates = <Completer<void>>[
      Completer<void>(),
      Completer<void>(),
    ];
    int i = 0;
    final Future<int> result = await start(
      tester,
      items: <String>['a.zip', 'b.zip'],
      each: (_) => gates[i++].future,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Moving 2 items'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('a.zip'), findsOneWidget);

    gates[0].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('b.zip'), findsOneWidget);

    gates[1].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Moved 2 items'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Moved 2 items'), findsNothing);
    expect(await result, 0);
  });

  testWidgets('a failure is counted and shown, not hidden behind a tick', (
    WidgetTester tester,
  ) async {
    final Future<int> result = await start(
      tester,
      items: <String>['a.zip', 'b.zip', 'c.zip'],
      each: (String s) async {
        if (s == 'b.zip') throw Exception('no');
      },
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('1 of 3 failed'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(await result, 1);
  });

  testWidgets('one long job counts the parts it reports, as extracting does', (
    WidgetTester tester,
  ) async {
    final StreamController<(int, int)> parts = StreamController<(int, int)>();
    final Completer<void> gate = Completer<void>();
    final Future<int> result = await start(
      tester,
      items: <String>['comic.zip'],
      each: (_) => gate.future,
      progress: parts.stream,
    );
    parts.add((53, 1500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Moving 1 items'), findsOneWidget);
    expect(find.text('54 of 1500'), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(await result, 0);
    unawaited(parts.close());
  });
}
