import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/app/floating_nav.dart';
import 'package:fotos/app/router.dart';
import 'package:fotos/app/save_pill.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/video_editor/domain/cut_plan.dart';
import 'package:fotos/features/video_editor/presentation/save_job.dart';
import 'package:fotos/features/video_editor/presentation/save_ring.dart';
import 'package:fotos/features/viewer/presentation/viewer_screen.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../support/fake_media_repository.dart';

class _NoEmpty extends EmptyAlbumsNotifier {
  @override
  Future<List<String>> build() async => const <String>[];
}

class _NoPrefs extends AlbumPrefsNotifier {
  @override
  Future<AlbumPrefs> build() async => const AlbumPrefs();
}

/// A 1x1 grey PNG.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81ytgAAAABJRU5ErkJggg==',
);

void main() {
  const MethodChannel channel = MethodChannel('my.minned.fotos/native');

  setUp(() {
    final TestDefaultBinaryMessenger m =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      channel,
      (MethodCall call) async => switch (call.method) {
        'cutVideo' || 'cutCancel' || 'askNotifications' => null,
        _ => throw MissingPluginException(),
      },
    );
    m.setMockMethodCallHandler(
      const MethodChannel('com.fluttercandies/photo_manager'),
      (MethodCall call) async => call.method == 'getThumb' ? _pixel : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> event(String method, Object? arg) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, arg),
            ),
            (_) {},
          );

  /// The app with a save started and hidden, 42% along.
  Future<ProviderContainer> openSaving(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          emptyAlbumsProvider.overrideWith(_NoEmpty.new),
          albumPrefsProvider.overrideWith(_NoPrefs.new),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
    final ProviderContainer c = ProviderScope.containerOf(
      tester.element(find.byType(FotosApp)),
    );
    await c
        .read(saveJobProvider.notifier)
        .start('5', 'Trip.mp4', CutPlan.whole(60000), replace: false);
    c.read(saveJobProvider.notifier).hide();
    await event('cutProgress', 42);
    await tester.pumpAndSettle();
    return c;
  }

  /// Steps [frames] frames of 16 ms, reading [measure] after each.
  Future<List<T>> film<T>(
    WidgetTester tester,
    int frames,
    T Function() measure,
  ) async {
    final List<T> out = <T>[];
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      out.add(measure());
    }
    return out;
  }

  /// The largest move between one frame and the next.
  double biggestStep(List<double> v) {
    double most = 0;
    for (int i = 1; i < v.length; i++) {
      most = (v[i] - v[i - 1]).abs() > most ? (v[i] - v[i - 1]).abs() : most;
    }
    return most;
  }

  testWidgets('on a pushed page the pill glides down into the tabs\' place, '
      'and back up as they return', (WidgetTester tester) async {
    final ProviderContainer c = await openSaving(tester);
    final double screen = tester.view.physicalSize.height / 2.625;
    double pillBottom() => tester.getRect(find.byType(SavePill)).bottom;
    final double aboveTabs = pillBottom();
    expect(aboveTabs, lessThan(tester.getRect(find.byType(FloatingNav)).top));

    c.read(routerProvider).push('/albums/favourites');
    final List<double> down = await film(tester, 30, pillBottom);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNav), findsNothing);
    expect(find.byType(SavePill), findsOneWidget);
    final double alone = pillBottom();
    expect(alone, greaterThan(aboveTabs + 40));
    expect(alone, lessThan(screen));
    // A glide, not a lurch: no 16 ms frame moves it more than an eighth of
    // the way (an even ease over 25 frames peaks near a twelfth), and it
    // never goes back up on its way down.
    expect(biggestStep(down), lessThan((alone - aboveTabs) / 8));
    for (int i = 1; i < down.length; i++) {
      expect(down[i], greaterThanOrEqualTo(down[i - 1] - 0.01));
    }

    c.read(routerProvider).pop();
    final List<double> up = await film(tester, 30, pillBottom);
    await tester.pumpAndSettle();
    expect(pillBottom(), moreOrLessEquals(aboveTabs, epsilon: 0.5));
    expect(biggestStep(up), lessThan((alone - aboveTabs) / 8));
  });

  testWidgets('the pill turns into the viewer\'s ring and back with nothing '
      'jumping at either end', (WidgetTester tester) async {
    final ProviderContainer c = await openSaving(tester);
    Rect ringIn(Finder f) => tester.getRect(
      find.descendant(of: f, matching: find.byType(SaveRingIndicator)),
    );
    final Rect pillRing = ringIn(find.byType(SavePill));
    final AssetEntity photo = AssetEntity(
      id: '1',
      typeInt: 1,
      width: 400,
      height: 300,
    );

    c
        .read(routerProvider)
        .push(
          '/viewer',
          extra: ViewerArgs(
            items: <AssetEntity>[photo],
            index: 0,
            heroPrefix: 'photos',
          ),
        );
    // Every frame, the one ring on screen (the flying copy's mid-flight),
    // from the frame the flight starts on.
    Rect flying() => tester.getRect(find.byType(SaveRingIndicator).last);
    await tester.pump();
    final List<Rect> there = <Rect>[
      flying(),
      ...await film(tester, 24, flying),
    ];
    await tester.pumpAndSettle();
    final Rect viewerRing = ringIn(find.byType(SaveRing));

    // It starts exactly where the pill's ring was and ends exactly on the
    // viewer's, at the top right.
    expect(
      there.first.center.dx,
      moreOrLessEquals(pillRing.center.dx, epsilon: 0.5),
    );
    expect(
      there.first.center.dy,
      moreOrLessEquals(pillRing.center.dy, epsilon: 0.5),
    );
    expect(
      there.last.center.dx,
      moreOrLessEquals(viewerRing.center.dx, epsilon: 0.5),
    );
    expect(
      there.last.center.dy,
      moreOrLessEquals(viewerRing.center.dy, epsilon: 0.5),
    );
    // Its size too: the pill's 28 at the start, the viewer's 24 at the end.
    expect(there.first.width, moreOrLessEquals(pillRing.width, epsilon: 0.5));
    expect(there.last.width, moreOrLessEquals(viewerRing.width, epsilon: 0.5));
    expect(
      viewerRing.center.dx,
      greaterThan(tester.view.physicalSize.width / 2.625 * 0.8),
    );
    // No frame carries it more than a fifth of the way.
    final double way = (viewerRing.center - pillRing.center).distance;
    for (int i = 1; i < there.length; i++) {
      expect(
        (there[i].center - there[i - 1].center).distance,
        lessThan(way / 5),
        reason: 'frame $i',
      );
    }

    // And back down into the pill.
    c.read(routerProvider).pop();
    await tester.pump();
    final List<Rect> back = <Rect>[flying(), ...await film(tester, 24, flying)];
    await tester.pumpAndSettle();
    expect(
      back.first.center.dx,
      moreOrLessEquals(viewerRing.center.dx, epsilon: 0.5),
    );
    expect(
      back.first.center.dy,
      moreOrLessEquals(viewerRing.center.dy, epsilon: 0.5),
    );
    expect(
      back.last.center.dx,
      moreOrLessEquals(pillRing.center.dx, epsilon: 0.5),
    );
    expect(
      back.last.center.dy,
      moreOrLessEquals(pillRing.center.dy, epsilon: 0.5),
    );
    for (int i = 1; i < back.length; i++) {
      expect(
        (back[i].center - back[i - 1].center).distance,
        lessThan(way / 5),
        reason: 'frame $i',
      );
    }
    expect(find.byType(SavePill), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
