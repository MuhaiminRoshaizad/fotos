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
}
