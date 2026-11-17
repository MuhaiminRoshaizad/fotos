import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/app/save_pill.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/video_editor/data/video_cutter.dart';
import 'package:fotos/features/video_editor/domain/cut_plan.dart';
import 'package:fotos/features/video_editor/presentation/save_end_listener.dart';
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

void main() {
  const MethodChannel channel = MethodChannel('my.minned.fotos/native');
  final List<String> calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call.method);
          return switch (call.method) {
            'cutVideo' || 'cutCancel' || 'askNotifications' => null,
            // Elsewhere, as if Android were not there.
            _ => throw MissingPluginException(),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// An event from Android, as SaveJob sends it.
  Future<void> event(String method, Object? arg) =>
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

  /// Starts a save and hides it, as Hide in its dialog does.
  Future<void> saveHidden(WidgetTester tester, ProviderContainer c) async {
    await c
        .read(saveJobProvider.notifier)
        .start('5', 'Trip.mp4', CutPlan.whole(60000), replace: false);
    c.read(saveJobProvider.notifier).hide();
    await event('cutProgress', 42);
    await tester.pumpAndSettle();
  }

  testWidgets('a hidden save shows as a pill above the tabs, which brings '
      'its dialog back', (WidgetTester tester) async {
    final ProviderContainer c = await open(tester);
    expect(find.byType(SavePill), findsNothing);

    await saveHidden(tester, c);
    expect(find.byType(SavePill), findsOneWidget);
    expect(find.text('Saving Trip.mp4'), findsOneWidget);
    expect(find.textContaining('42%'), findsOneWidget);
    expect(calls, contains('askNotifications'));

    await tester.tap(find.byType(SavePill));
    await tester.pumpAndSettle();
    expect(find.byType(SavingDialog), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    // Cancel on the left, Hide on the right, as iOS lays out two actions.
    expect(
      tester.getCenter(find.text('Cancel')).dx,
      lessThan(tester.getCenter(find.text('Hide')).dx),
    );

    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.byType(SavingDialog), findsNothing);
    expect(find.byType(SavePill), findsOneWidget);

    // Opened again, the dialog closes itself when the save ends.
    await tester.tap(find.byType(SavePill));
    await tester.pumpAndSettle();
    await event('cutDone', <String, Object>{
      'id': '',
      'name': 'Trip (edited).mp4',
      'replaced': false,
    });
    await tester.pumpAndSettle();
    expect(find.byType(SavingDialog), findsNothing);
    expect(find.byType(SavePill), findsNothing);
    expect(find.text('Saved Trip (edited).mp4'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('Cancel from the pill ends the save and says the original is '
      'unchanged', (WidgetTester tester) async {
    final ProviderContainer c = await open(tester);
    await saveHidden(tester, c);
    await tester.tap(find.byType(SavePill));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Nothing stops until it is confirmed.
    expect(calls, isNot(contains('cutCancel')));
    expect(find.text('Stop saving?'), findsOneWidget);
    expect(
      find.text('The edit will be lost. Trip.mp4 stays as it is.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep Saving'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('cutCancel')));
    expect(find.text('Saving video'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop Saving'));
    await tester.pump();
    expect(calls, contains('cutCancel'));
    await event('cutDone', <String, Object>{
      'error': 'cancelled',
      'message': 'Cancelled',
    });
    await tester.pumpAndSettle();
    expect(find.byType(SavingDialog), findsNothing);
    expect(find.text('Save cancelled. Trip.mp4 is unchanged.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('a save that ends while Stop saving? is asked closes it, with '
      'nothing left asking', (WidgetTester tester) async {
    final ProviderContainer c = await open(tester);
    await saveHidden(tester, c);
    await tester.tap(find.byType(SavePill));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Stop saving?'), findsOneWidget);

    await event('cutDone', <String, Object>{
      'id': '',
      'name': 'Trip (edited).mp4',
      'replaced': false,
    });
    await tester.pumpAndSettle();
    expect(find.text('Stop saving?'), findsNothing);
    expect(find.byType(SavingDialog), findsNothing);
    expect(calls, isNot(contains('cutCancel')));
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  test('how a hidden save ending is told', () {
    HiddenEnd end(SaveEnd e) => (name: 'Trip.mp4', end: e);
    expect(
      toldEnd(
        end(
          const SaveEnd.saved(
            SavedEdit(id: '9', name: 'Trip.mp4', replaced: true),
          ),
        ),
      ),
      (message: 'Replaced Trip.mp4 with the edit', failed: false),
    );
    expect(
      toldEnd(
        end(
          const SaveEnd.saved(
            SavedEdit(id: '9', name: 'Trip (edited).mp4', replaced: false),
          ),
        ),
      ),
      (message: 'Saved Trip (edited).mp4', failed: false),
    );
    expect(
      toldEnd(
        end(const SaveEnd.failed(CutException(CutFailure.noSpace, null))),
      ),
      (
        message:
            'Couldn\'t save the edit: not enough free space. '
            'Trip.mp4 is unchanged.',
        failed: true,
      ),
    );
    expect(
      toldEnd(end(const SaveEnd.failed(CutException(CutFailure.failed, null)))),
      (
        message: 'Couldn\'t save the edit. Trip.mp4 is unchanged.',
        failed: true,
      ),
    );
  });
}
