import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/platform/native_channel.dart';
import 'package:fotos/features/video_editor/data/video_cutter.dart';
import 'package:fotos/features/video_editor/domain/cut_plan.dart';
import 'package:fotos/features/video_editor/presentation/save_job.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('my.minned.fotos/native');
  final List<MethodCall> calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return reply(call);
        });
  }

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

  setUp(calls.clear);

  test(
    'starts a save with the kept parts in order and the file name',
    () async {
      answer((_) => null);
      CutPlan plan = CutPlan.whole(100000).move(const Handle.start(), 8000);
      (plan, _) = plan.addCut(50000)!;
      await VideoCutter(
        NativeChannel(),
      ).start('12', plan, replace: false, name: 'Trip.mp4');

      final Map<Object?, Object?> args =
          calls.single.arguments as Map<Object?, Object?>;
      expect(calls.single.method, 'cutVideo');
      expect(args['id'], '12');
      expect(args['replace'], false);
      expect(args['name'], 'Trip.mp4');
      expect(args['keep'], <List<int>>[
        <int>[8000, 45000],
        <int>[55000, 100000],
      ]);
    },
  );

  test('a save already running refuses another as busy', () async {
    answer((_) => throw PlatformException(code: 'busy', message: 'why'));
    await expectLater(
      VideoCutter(
        NativeChannel(),
      ).start('1', CutPlan.whole(10000), replace: true, name: 'a.mp4'),
      throwsA(
        isA<CutException>().having(
          (CutException e) => e.reason,
          'reason',
          CutFailure.busy,
        ),
      ),
    );
  });

  test('the end reads back the saved video', () {
    final SaveEnd end = endOf(<Object?, Object?>{
      'id': '77',
      'name': 'Trip (edited).mp4',
      'replaced': false,
    });
    expect(end.error, isNull);
    expect(end.saved!.id, '77');
    expect(end.saved!.name, 'Trip (edited).mp4');
    expect(end.saved!.replaced, isFalse);
  });

  test('each error from Android comes back as its own reason', () {
    for (final (String code, CutFailure reason) in <(String, CutFailure)>[
      ('no_access', CutFailure.noAccess),
      ('no_space', CutFailure.noSpace),
      ('cancelled', CutFailure.cancelled),
      ('busy', CutFailure.busy),
      ('failed', CutFailure.failed),
      ('anything else', CutFailure.failed),
    ]) {
      final SaveEnd end = endOf(<Object?, Object?>{
        'error': code,
        'message': 'why',
      });
      expect(end.saved, isNull);
      expect(end.error!.reason, reason, reason: code);
      expect(end.error!.detail, 'why');
    }
  });

  group('the save job', () {
    late ProviderContainer c;

    setUp(() {
      answer((_) => null);
      c = ProviderContainer();
      // Kept alive as the app keeps it, by being listened to.
      c.listen(saveJobProvider, (_, _) {});
    });

    tearDown(() => c.dispose());

    Future<Future<SavedEdit?>> start({bool replace = true}) => c
        .read(saveJobProvider.notifier)
        .start('5', 'Trip.mp4', CutPlan.whole(60000), replace: replace);

    test('follows the progress and completes with the saved video', () async {
      final Future<SavedEdit?> saving = await start();
      expect(c.read(saveJobProvider)?.name, 'Trip.mp4');
      expect(c.read(saveJobProvider)?.percent, 0);
      expect(c.read(saveJobProvider)?.hidden, isFalse);

      await event('cutProgress', 42);
      expect(c.read(saveJobProvider)?.percent, 42);

      await event('cutDone', <String, Object>{
        'id': '9',
        'name': 'Trip.mp4',
        'replaced': true,
      });
      final SavedEdit? saved = await saving;
      expect(saved!.id, '9');
      expect(saved.replaced, isTrue);
      expect(c.read(saveJobProvider), isNull);
    });

    test('a failure ends the job and is thrown', () async {
      final Future<SavedEdit?> saving = await start(replace: false);
      final Future<void> thrown = expectLater(
        saving,
        throwsA(
          isA<CutException>().having(
            (CutException e) => e.reason,
            'reason',
            CutFailure.noSpace,
          ),
        ),
      );
      await event('cutDone', <String, Object>{
        'error': 'no_space',
        'message': 'full',
      });
      await thrown;
      expect(c.read(saveJobProvider), isNull);
    });

    test('Cancel asks Android to stop the save', () async {
      await c.read(saveJobProvider.notifier).cancel();
      expect(calls.last.method, 'cutCancel');
    });

    test('Hide lets the editor go, asks to notify, and the end is told '
        'by the app', () async {
      final Future<SavedEdit?> saving = await start();
      final List<HiddenEnd> told = <HiddenEnd>[];
      c.read(saveJobProvider.notifier).hiddenEnds.listen(told.add);

      c.read(saveJobProvider.notifier).hide();
      expect(await saving, isNull);
      expect(c.read(saveJobProvider)?.hidden, isTrue);
      expect(calls.last.method, 'askNotifications');

      await event('cutProgress', 70);
      expect(c.read(saveJobProvider)?.percent, 70);
      await event('cutDone', <String, Object>{
        'id': '9',
        'name': 'Trip (edited).mp4',
        'replaced': false,
      });
      await Future<void>.delayed(Duration.zero);
      expect(c.read(saveJobProvider), isNull);
      expect(told.single.name, 'Trip.mp4');
      expect(told.single.end.saved!.name, 'Trip (edited).mp4');
    });
  });

  test('a fotos opened midway picks up the save, as a hidden one', () async {
    answer(
      (MethodCall call) => call.method == 'cutStatus'
          ? <String, Object>{'running': true, 'percent': 35, 'name': 'Trip.mp4'}
          : null,
    );
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(saveJobProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final SaveJob? job = c.read(saveJobProvider);
    expect(job?.name, 'Trip.mp4');
    expect(job?.percent, 35);
    expect(job?.hidden, isTrue);
  });
}
