import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/platform/native_channel.dart';
import 'package:fotos/core/video/video_frames.dart';

/// Answers each read when the test says so; a picture's moment is the
/// stretch's start, as for a video with no keyframe inside it.
class _Source implements FrameSource {
  final List<({Stretch s, Completer<VideoFrame?> done})> reads =
      <({Stretch s, Completer<VideoFrame?> done})>[];
  int closes = 0;

  @override
  Future<VideoFrame?> frameIn(int from, int until) {
    final Completer<VideoFrame?> done = Completer<VideoFrame?>();
    reads.add((s: (from: from, until: until), done: done));
    return done.future;
  }

  void answer(int i, {int? ms}) {
    final Stretch s = reads[i].s;
    reads[i].done.complete((ms: ms ?? s.from, jpeg: Uint8List(1)));
  }

  @override
  void close() => closes++;
}

List<Stretch> _tiles(int from, int step, int count) => <Stretch>[
  for (int i = 0; i < count; i++)
    (from: from + i * step, until: from + (i + 1) * step),
];

void main() {
  test('each picture shows as soon as it is read, not with the rest', () async {
    final _Source source = _Source();
    final VideoFrames frames = VideoFrames(source);
    addTearDown(frames.dispose);
    int changes = 0;
    frames.addListener(() => changes++);

    frames.want(_tiles(0, 1000, 3), focus: 0);
    source.answer(1);
    await pumpEventQueue();

    expect(changes, 1);
    expect(frames.frameIn(1000, 2000), isNotNull);
    expect(frames.frameIn(0, 1000), isNull);
    expect(frames.loading(0, 1000), isTrue);
  });

  test('reads three at a time, nearest the playhead first', () async {
    final _Source source = _Source();
    final VideoFrames frames = VideoFrames(source);
    addTearDown(frames.dispose);

    frames.want(_tiles(0, 1000, 8), focus: 5500);

    expect(source.reads.map((r) => r.s.from), <int>[5000, 6000, 4000]);
    source.answer(0);
    await pumpEventQueue();
    expect(source.reads.length, 4);
    expect(source.reads.last.s.from, 7000);
  });

  test('a tile never borrows a picture from outside its stretch', () async {
    final _Source source = _Source();
    final VideoFrames frames = VideoFrames(source);
    addTearDown(frames.dispose);

    frames.want(_tiles(0, 1000, 1), focus: 0);
    source.answer(0);
    await pumpEventQueue();

    expect(frames.frameIn(0, 1000), isNotNull);
    expect(frames.frameIn(1000, 2000), isNull);
    expect(frames.frameIn(60000, 61000), isNull);
  });

  test('zooming in keeps every picture already showing in place', () async {
    final _Source source = _Source();
    final VideoFrames frames = VideoFrames(source);
    addTearDown(frames.dispose);

    // Two 16 s tiles; the second's picture is a keyframe at 20 s.
    frames.want(_tiles(0, 16000, 2), focus: 0);
    source.answer(0);
    source.answer(1, ms: 20000);
    await pumpEventQueue();
    final Uint8List? first = frames.frameIn(0, 16000);
    final Uint8List? second = frames.frameIn(16000, 32000);

    // Split into 8 s tiles: each picture is in the half holding its moment,
    // and only the other halves are read.
    final List<Stretch> halves = _tiles(0, 8000, 4);
    frames.want(halves, focus: 0);

    expect(frames.frameIn(0, 8000), same(first));
    expect(frames.frameIn(16000, 24000), same(second));
    expect(source.reads.skip(2).map((r) => r.s.from), <int>[8000, 24000]);
  });

  test('a stretch that cannot be read is not asked for again', () async {
    final _Source source = _Source();
    final VideoFrames frames = VideoFrames(source);
    addTearDown(frames.dispose);

    frames.want(_tiles(0, 1000, 1), focus: 0);
    source.reads.single.done.complete(null);
    await pumpEventQueue();
    frames.want(_tiles(0, 1000, 1), focus: 0);

    expect(source.reads.length, 1);
    expect(frames.loading(0, 1000), isFalse);
  });

  test(
    'keeps at most a few hundred pictures, those nearest the playhead',
    () async {
      final _Source source = _Source();
      final VideoFrames frames = VideoFrames(source);
      addTearDown(frames.dispose);

      // Scrolling through 1000 seconds, a screenful at a time.
      for (int at = 0; at < 1000; at += 10) {
        frames.want(_tiles(at * 1000, 1000, 10), focus: (at + 5) * 1000);
        for (int i = 0; i < 10; i++) {
          final int next = source.reads.indexWhere((r) => !r.done.isCompleted);
          if (next < 0) break;
          source.answer(next);
          await pumpEventQueue();
        }
      }

      int kept = 0;
      for (int t = 0; t < 1000; t++) {
        if (frames.frameIn(t * 1000, t * 1000 + 1) != null) kept++;
      }
      expect(kept, VideoFrames.keep);
      expect(frames.frameIn(999000, 1000000), isNotNull);
      expect(frames.frameIn(0, 1000), isNull);
    },
  );

  test(
    'lets go of the file once idle, and opens it again when asked',
    () async {
      final _Source source = _Source();
      final VideoFrames frames = VideoFrames(
        source,
        idleAfter: const Duration(milliseconds: 50),
      );
      addTearDown(frames.dispose);

      frames.want(_tiles(0, 1000, 1), focus: 0);
      source.answer(0);
      await pumpEventQueue();
      expect(source.closes, 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(source.closes, 1);

      frames.want(_tiles(1000, 1000, 1), focus: 1000);
      expect(source.reads.length, 2);
    },
  );

  test('the native reader is opened once and its pictures come back', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const MethodChannel channel = MethodChannel('my.minned.fotos/native');
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return switch (call.method) {
            'videoFramesOpen' => 7,
            'videoFrameIn' => <String, Object?>{
              'ms': 2000,
              'jpeg': Uint8List.fromList(<int>[9]),
            },
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final NativeFrameSource source = NativeFrameSource(
      const NativeChannel(),
      '/v.mp4',
      192,
    );
    final VideoFrame? a = await source.frameIn(0, 4000);
    await source.frameIn(4000, 8000);
    source.close();
    await pumpEventQueue();

    expect(a?.ms, 2000);
    expect(calls.map((MethodCall c) => c.method), <String>[
      'videoFramesOpen',
      'videoFrameIn',
      'videoFrameIn',
      'videoFramesClose',
    ]);
  });
}
