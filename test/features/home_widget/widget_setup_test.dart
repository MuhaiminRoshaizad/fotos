import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/features/home_widget/domain/widget_config.dart';
import 'package:fotos/features/home_widget/presentation/widget_setup_screen.dart';
import 'package:photo_manager/photo_manager.dart';

Album _album(String id, String name, int count) => Album(
  id: id,
  name: name,
  count: count,
  path: AssetPathEntity(id: id, name: name),
);

void main() {
  final List<Album> albums = <Album>[
    _album('1', 'Family', 120),
    _album('2', 'Screenshots', 300),
    _album('3', 'WhatsApp Images', 268),
    _album('4', 'Travel', 40),
  ];

  late List<WidgetConfig> done;
  late int cancelled;

  Future<void> open(WidgetTester tester, {WidgetConfig? initial}) async {
    done = <WidgetConfig>[];
    cancelled = 0;
    tester.view.physicalSize = const Size(400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [albumsProvider.overrideWith((Ref ref) async => albums)],
        child: MaterialApp(
          home: WidgetSetupScreen(
            initial: initial,
            onDone: done.add,
            onCancel: () => cancelled++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('settings survive the trip to Android and back', () {
    const WidgetConfig c = WidgetConfig(
      show: WidgetShow.videos,
      source: WidgetSource.albums,
      albums: <String>{'1', '4'},
      leaveOut: <String>{'2'},
      order: WidgetOrder.years,
      every: 900,
      fit: WidgetFit.fill,
      caption: WidgetCaption.ago,
      skip: false,
    );
    final WidgetConfig back = WidgetConfig.fromMap(c.toMap());
    expect(back.toMap(), c.toMap());
  });

  test('unknown or missing values fall back to the defaults', () {
    final WidgetConfig c = WidgetConfig.fromMap(<Object?, Object?>{
      'show': 'holograms',
      'every': 7,
    });
    expect(c.show, WidgetShow.photos);
    expect(c.every, 10);
    expect(c.skip, isTrue);
  });

  testWidgets(
    'a new widget leaves out screenshots and WhatsApp to begin with',
    (WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(done.single.source, WidgetSource.all);
      expect(done.single.leaveOut, <String>{'2', '3'});
    },
  );

  testWidgets('chosen albums needs one before Done is allowed', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Chosen albums'));
    await tester.pumpAndSettle();
    expect(find.text('Albums to show'), findsOneWidget);
    expect(find.text('Pick at least one album.'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(done, isEmpty);

    await tester.tap(find.text('Family'));
    await tester.pump();
    await tester.tap(find.text('Travel'));
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsNWidgets(2));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(done.single.albums, <String>{'1', '4'});
  });

  testWidgets('choices are kept, and Cancel reports nothing chosen', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Videos'));
    await tester.tap(find.text('Spread across years'));
    await tester.tap(find.text('15 min'));
    await tester.tap(find.text('How long ago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final WidgetConfig c = done.single;
    expect(c.show, WidgetShow.videos);
    expect(c.order, WidgetOrder.years);
    expect(c.every, 900);
    expect(c.caption, WidgetCaption.ago);

    await tester.tap(find.text('Cancel'));
    expect(cancelled, 1);
  });

  testWidgets('a widget set up before opens on its own settings', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      initial: const WidgetConfig(
        source: WidgetSource.albums,
        albums: <String>{'4'},
        every: 3600,
      ),
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(done.single.albums, <String>{'4'});
    expect(done.single.every, 3600);
    // A saved widget keeps what it had; no defaults are added.
    expect(done.single.leaveOut, isEmpty);
  });
}
