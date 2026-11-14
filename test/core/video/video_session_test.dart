import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/video/video_session.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Records what each player is asked to do and lets a test end a video.
class _FakePlatform extends VideoPlayerPlatform {
  final List<String> calls = <String>[];
  final Map<int, StreamController<VideoEvent>> events =
      <int, StreamController<VideoEvent>>{};
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final int id = _next++;
    events[id] = StreamController<VideoEvent>();
    calls.add('create $id');
    scheduleMicrotask(
      () => events[id]!.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 6),
          size: const Size(1920, 1080),
        ),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => calls.add('dispose $playerId');

  @override
  Future<void> play(int playerId) async => calls.add('play $playerId');

  @override
  Future<void> pause(int playerId) async => calls.add('pause $playerId');

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      calls.add('seek $playerId ${position.inSeconds}');

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  void end(int playerId) =>
      events[playerId]!.add(VideoEvent(eventType: VideoEventType.completed));
}

void main() {
  late _FakePlatform platform;
  late VideoSession session;

  Future<VideoPlayerController> open() async {
    final VideoPlayerController c = VideoPlayerController.networkUrl(
      Uri.parse('https://example.invalid/video.mp4'),
    );
    await c.initialize();
    return c;
  }

  /// Lets queued platform calls and the seek timers run.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  /// Stops the plugin's position timer before the test's timer check.
  Future<void> close(WidgetTester tester) async {
    session.dispose();
    await settle(tester);
  }

  setUp(() {
    platform = _FakePlatform();
    VideoPlayerPlatform.instance = platform;
    session = VideoSession(open);
  });

  testWidgets('before the end, seeks and play go to the one player', (
    WidgetTester tester,
  ) async {
    await session.start();
    session.seekTo(const Duration(seconds: 3));
    session.play();
    await settle(tester);

    expect(platform.calls, containsAllInOrder(<String>['seek 0 3', 'play 0']));
    expect(platform.calls, isNot(contains('create 1')));
    expect(session.target, isNull);
    await close(tester);
  });

  testWidgets('a session disposed while its player opens releases that '
      'player', (WidgetTester tester) async {
    final Completer<void> gate = Completer<void>();
    final VideoSession slow = VideoSession(() async {
      await gate.future;
      return open();
    });
    final Future<void> starting = slow.start();
    slow.dispose();
    gate.complete();
    await tester.runAsync(pumpEventQueue);
    await settle(tester);
    await starting;
    await tester.runAsync(pumpEventQueue);
    await settle(tester);

    expect(platform.calls, contains('create 0'));
    expect(platform.calls, contains('dispose 0'));
    session.dispose();
  });

  testWidgets('play after the end starts a new player from the beginning', (
    WidgetTester tester,
  ) async {
    await session.start();
    session.play();
    await settle(tester);
    platform.end(0);
    await settle(tester);
    platform.calls.clear();

    session.play();
    await settle(tester);

    expect(
      platform.calls,
      containsAllInOrder(<String>['create 1', 'seek 1 0', 'play 1']),
    );
    // The old player is let go only after the new one is in place; the
    // plugin's dispose needs real event-loop turns to finish.
    await tester.runAsync(pumpEventQueue);
    await settle(tester);
    expect(platform.calls, contains('dispose 0'));
    expect(platform.calls.where((String c) => c == 'play 0'), isEmpty);
    expect(session.target, isNull);
    await close(tester);
  });

  testWidgets('a scrub after the end lands on a new player, still paused', (
    WidgetTester tester,
  ) async {
    await session.start();
    platform.end(0);
    await settle(tester);
    platform.calls.clear();

    session.seekTo(const Duration(seconds: 2));
    session.seekTo(const Duration(seconds: 4));
    await settle(tester);

    expect(platform.calls.where((String c) => c.startsWith('create')), <String>[
      'create 1',
    ]);
    expect(platform.calls, contains('seek 1 4'));
    expect(platform.calls, isNot(contains('play 1')));
    expect(platform.calls.where((String c) => c.startsWith('seek 0')), isEmpty);

    // The new player is an ordinary one: its seeks go straight to it.
    platform.calls.clear();
    session.seekTo(const Duration(seconds: 1));
    await settle(tester);
    expect(platform.calls, <String>['seek 1 1']);
    await close(tester);
  });
}
