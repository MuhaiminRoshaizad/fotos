import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/platform/native_channel.dart';
import 'package:fotos/features/video_editor/data/video_cutter.dart';
import 'package:fotos/features/video_editor/domain/cut_plan.dart';

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

  setUp(calls.clear);

  test(
    'sends the kept parts in order and reads back the saved video',
    () async {
      answer(
        (_) => <String, Object>{
          'id': '77',
          'name': 'Trip (edited).mp4',
          'replaced': false,
        },
      );
      CutPlan plan = CutPlan.whole(100000).move(const Handle.start(), 8000);
      (plan, _) = plan.addCut(50000)!;
      final SavedEdit saved = await VideoCutter(
        NativeChannel(),
      ).save('12', plan, replace: false);

      final Map<Object?, Object?> args =
          calls.single.arguments as Map<Object?, Object?>;
      expect(calls.single.method, 'cutVideo');
      expect(args['id'], '12');
      expect(args['replace'], false);
      expect(args['keep'], <List<int>>[
        <int>[8000, 45000],
        <int>[55000, 100000],
      ]);
      expect(saved.id, '77');
      expect(saved.name, 'Trip (edited).mp4');
      expect(saved.replaced, isFalse);
    },
  );

  test('each refusal from Android comes back as its own reason', () async {
    for (final (String code, CutFailure reason) in <(String, CutFailure)>[
      ('no_access', CutFailure.noAccess),
      ('no_space', CutFailure.noSpace),
      ('cancelled', CutFailure.cancelled),
      ('busy', CutFailure.busy),
      ('after_trash', CutFailure.afterTrash),
      ('failed', CutFailure.failed),
      ('anything else', CutFailure.failed),
    ]) {
      answer((_) => throw PlatformException(code: code, message: 'why'));
      await expectLater(
        VideoCutter(
          NativeChannel(),
        ).save('1', CutPlan.whole(10000), replace: true),
        throwsA(
          isA<CutException>()
              .having((CutException e) => e.reason, 'reason', reason)
              .having((CutException e) => e.detail, 'detail', 'why'),
        ),
      );
    }
  });

  group('progress by length', () {
    // Half a second kept before a cut, then 54 minutes.
    const List<int> parts = <int>[500, 3240000];

    test('a tiny first part no longer counts as half the save', () {
      // Media3 reports 50% once the half second is done.
      expect(byLength(50, parts), 0);
      // and 75% half way through the long part.
      expect(byLength(75, parts), 50);
      expect(byLength(99, parts), 98);
    });

    test('parts of equal length read as Media3 reports them', () {
      expect(byLength(25, <int>[1000, 1000]), 25);
      expect(byLength(60, <int>[1000, 1000]), 60);
    });

    test('one part, and the finish, pass straight through', () {
      expect(byLength(37, <int>[5000]), 37);
      expect(byLength(100, parts), 100);
    });

    test('never runs backwards as Media3 counts up', () {
      const List<int> three = <int>[60000, 2000, 900000];
      int last = 0;
      for (int p = 0; p < 100; p++) {
        final int now = byLength(p, three);
        expect(now, greaterThanOrEqualTo(last), reason: 'at $p%');
        last = now;
      }
    });
  });
}
