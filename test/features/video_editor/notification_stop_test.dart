import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/app/save_pill.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/video_editor/domain/cut_plan.dart';
import 'package:fotos/features/video_editor/presentation/save_job.dart';
import 'package:fotos/features/video_editor/presentation/save_progress.dart';

import '../../support/fake_media_repository.dart';

class _NoEmpty extends EmptyAlbumsNotifier {
  @override
  Future<List<String>> build() async => const <String>[];
}

class _NoPrefs extends AlbumPrefsNotifier {
  @override
  Future<AlbumPrefs> build() async => const AlbumPrefs();
}

/// The save notification's Stop...: it opens fotos to ask, never stops by
/// itself, and holds up whatever fotos was doing when it was tapped.
void main() {
  const MethodChannel channel = MethodChannel('my.minned.fotos/native');
  final List<String> calls = <String>[];

  /// What Android answers: whether fotos was opened by Stop..., and the
  /// save it is running when fotos starts.
  bool launchedToAsk = false;
  Map<String, Object>? running;

  setUp(() {
    calls.clear();
    launchedToAsk = false;
    running = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call.method);
          return switch (call.method) {
            'cutVideo' || 'cutCancel' || 'askNotifications' => null,
            'launchAsksStop' => launchedToAsk,
            'cutStatus' => running,
            _ => throw MissingPluginException(),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> event(String method, [Object? arg]) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, arg),
            ),
            (_) {},
          );

  Future<ProviderContainer> open(WidgetTester tester) async {
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
    return ProviderScope.containerOf(tester.element(find.byType(FotosApp)));
  }

  Future<void> saveHidden(
    WidgetTester tester,
    ProviderContainer c, {
    int percent = 42,
  }) async {
    await c
        .read(saveJobProvider.notifier)
        .start('5', 'Trip.mp4', CutPlan.whole(60000), replace: false);
    c.read(saveJobProvider.notifier).hide();
    await event('cutProgress', percent);
    // At 100 the ring spins until the file is ready, so nothing settles.
    percent < 100
        ? await tester.pumpAndSettle()
        : await tester.pump(const Duration(seconds: 1));
  }

  Future<void> done(WidgetTester tester) async {
    await event('cutDone', <String, Object>{
      'id': '',
      'name': 'Trip (edited).mp4',
      'replaced': false,
    });
    await tester.pumpAndSettle(const Duration(seconds: 6));
  }

  testWidgets('with fotos running, Stop... opens the question and only the '
      'answer stops', (WidgetTester tester) async {
    final ProviderContainer c = await open(tester);
    await saveHidden(tester, c);

    await event('askStopSave');
    await tester.pumpAndSettle();
    expect(find.byType(SavingDialog), findsOneWidget);
    expect(find.text('Stop saving?'), findsOneWidget);
    expect(calls, isNot(contains('cutCancel')));

    // Keep Saving leaves it running, on the progress.
    await tester.tap(find.text('Keep Saving'));
    await tester.pumpAndSettle();
    expect(find.text('Saving video'), findsOneWidget);
    expect(calls, isNot(contains('cutCancel')));

    // Asked again, Stop Saving stops it.
    await event('askStopSave');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop Saving'));
    await tester.pump();
    expect(calls, contains('cutCancel'));
    await event('cutDone', <String, Object>{
      'error': 'cancelled',
      'message': 'Cancelled',
    });
    await tester.pumpAndSettle(const Duration(seconds: 6));
    expect(find.byType(SavingDialog), findsNothing);
  });

  testWidgets('with the saving dialog already open, Stop... turns it to the '
      'question instead of opening a second', (WidgetTester tester) async {
    final ProviderContainer c = await open(tester);
    await saveHidden(tester, c);
    await tester.tap(find.byType(SavePill));
    await tester.pumpAndSettle();
    expect(find.text('Saving video'), findsOneWidget);

    await event('askStopSave');
    await tester.pumpAndSettle();
    expect(find.byType(SavingDialog), findsOneWidget);
    expect(find.text('Stop saving?'), findsOneWidget);
    await done(tester);
    expect(find.byType(SavingDialog), findsNothing);
  });

  testWidgets('tapped twice in a row, Stop... still opens one dialog', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = await open(tester);
    await saveHidden(tester, c);
    await event('askStopSave');
    await event('askStopSave');
    await tester.pump();
    await event('askStopSave');
    await tester.pumpAndSettle();
    expect(find.byType(SavingDialog), findsOneWidget);
    expect(find.text('Stop saving?'), findsOneWidget);
    await done(tester);
  });

  testWidgets('if the save ended before fotos came up, Stop... asks nothing', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = await open(tester);
    await saveHidden(tester, c);
    await done(tester);

    await event('askStopSave');
    await tester.pumpAndSettle();
    expect(find.byType(SavingDialog), findsNothing);
    expect(find.text('Stop saving?'), findsNothing);
  });

  testWidgets('at the finishing step it is too late to stop: the progress '
      'shows, with no way to stop', (WidgetTester tester) async {
    final ProviderContainer c = await open(tester);
    await saveHidden(tester, c, percent: 100);
    await event('askStopSave');
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SavingDialog), findsOneWidget);
    expect(find.text('Stop saving?'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SavingDialog),
        matching: find.text('Finishing'),
      ),
      findsOneWidget,
    );
    await done(tester);
  });

  testWidgets('opened from cold by Stop..., fotos picks up the save first and '
      'then asks', (WidgetTester tester) async {
    launchedToAsk = true;
    running = <String, Object>{
      'running': true,
      'name': 'Trip.mp4',
      'percent': 37,
    };
    await open(tester);
    expect(calls, containsAllInOrder(<String>['cutStatus', 'launchAsksStop']));
    expect(find.byType(SavingDialog), findsOneWidget);
    expect(find.text('Stop saving?'), findsOneWidget);
    expect(
      find.text('The edit will be lost. Trip.mp4 stays as it is.'),
      findsOneWidget,
    );
    expect(calls, isNot(contains('cutCancel')));
    await done(tester);
  });

  testWidgets('opened from cold the usual way, nothing is asked', (
    WidgetTester tester,
  ) async {
    running = <String, Object>{
      'running': true,
      'name': 'Trip.mp4',
      'percent': 37,
    };
    await open(tester);
    expect(find.byType(SavingDialog), findsNothing);
    expect(find.byType(SavePill), findsOneWidget);
    await done(tester);
  });
}
