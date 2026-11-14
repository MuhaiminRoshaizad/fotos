import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/platform/native_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the filmstrip frames come back in one call, a missing one as null',
    () async {
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('my.minned.fotos/native'),
            (MethodCall call) async {
              calls.add(call);
              return <Object?>[
                Uint8List.fromList(<int>[1]),
                null,
                Uint8List.fromList(<int>[3]),
              ];
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('my.minned.fotos/native'),
              null,
            ),
      );

      final List<Uint8List?> frames = await const NativeChannel().videoFrames(
        '/v.mp4',
        3,
        192,
      );

      expect(calls.single.method, 'videoFrames');
      expect(calls.single.arguments, <String, Object>{
        'path': '/v.mp4',
        'count': 3,
        'px': 192,
      });
      expect(frames.map((Uint8List? f) => f?.first), <int?>[1, null, 3]);
    },
  );

  test('a frame reader opens, reads a stretch and closes by id', () async {
    final List<MethodCall> calls = <MethodCall>[];
    const MethodChannel channel = MethodChannel('my.minned.fotos/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return switch (call.method) {
            'videoFramesOpen' => 4,
            'videoFrameIn' when call.arguments['from'] == 0 =>
              <String, Object?>{
                'ms': 1500,
                'jpeg': Uint8List.fromList(<int>[5]),
              },
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const NativeChannel native = NativeChannel();

    final int id = await native.videoFramesOpen('/v.mp4', 192);
    final ({int ms, Uint8List jpeg})? got = await native.videoFrameIn(
      id,
      0,
      2000,
    );
    final ({int ms, Uint8List jpeg})? none = await native.videoFrameIn(
      id,
      2000,
      4000,
    );
    await native.videoFramesClose(id);

    expect(got?.ms, 1500);
    expect(got?.jpeg, <int>[5]);
    expect(none, isNull);
    expect(calls.first.arguments, <String, Object>{
      'path': '/v.mp4',
      'px': 192,
    });
    expect(calls[1].arguments, <String, Object>{
      'id': 4,
      'from': 0,
      'until': 2000,
    });
    expect(calls.last.method, 'videoFramesClose');
  });
}
