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
}
