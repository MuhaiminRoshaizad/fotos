import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/app/floating_nav.dart';
import 'package:fotos/app/tab_order.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fake_media_repository.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('a saved order is used only when it names all four tabs once', () {
    expect(
      decodeTabOrder(<String>['/videos', '/photos', '/albums', '/files']),
      <int>[1, 0, 2, 3],
    );
    expect(decodeTabOrder(null), defaultTabOrder);
    expect(decodeTabOrder(<String>['/videos', '/photos']), defaultTabOrder);
    expect(
      decodeTabOrder(<String>['/videos', '/videos', '/albums', '/files']),
      defaultTabOrder,
    );
  });

  Future<void> open(WidgetTester tester, List<int> order) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          initialTabOrderProvider.overrideWithValue(order),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> barLabels(WidgetTester tester) {
    final List<String> labels = <String>['Photos', 'Videos', 'Albums', 'Files'];
    labels.sort(
      (String a, String b) => tester
          .getCenter(find.bySemanticsLabel(a).last)
          .dx
          .compareTo(tester.getCenter(find.bySemanticsLabel(b).last).dx),
    );
    return labels;
  }

  testWidgets('fotos opens on the first tab of the saved order, and the bar '
      'follows it', (WidgetTester tester) async {
    await open(tester, <int>[1, 0, 2, 3]);
    expect(tester.widget<FloatingNav>(find.byType(FloatingNav)).index, 1);
    expect(barLabels(tester), <String>['Videos', 'Photos', 'Albums', 'Files']);
  });

  testWidgets('holding the bar opens Edit tabs; a dragged tab and Done keep '
      'the new order', (WidgetTester tester) async {
    await open(tester, defaultTabOrder);
    await tester.longPress(find.byType(FloatingNav));
    await tester.pumpAndSettle();
    expect(find.text('Edit tabs'), findsOneWidget);
    expect(find.text('Opens first'), findsOneWidget);

    // Drag Photos down below Albums.
    final TestGesture g = await tester.startGesture(
      // Photos is the first row, so its grip is the first.
      tester.getCenter(find.byIcon(CupertinoIcons.line_horizontal_3).first),
    );
    for (int i = 0; i < 12; i++) {
      await g.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Edit tabs'), findsNothing);
    expect(barLabels(tester), <String>['Videos', 'Albums', 'Photos', 'Files']);
    expect(
      await SharedPreferencesAsync().getStringList(TabOrderNotifier.key),
      <String>['/videos', '/albums', '/photos', '/files'],
    );
  });
}
