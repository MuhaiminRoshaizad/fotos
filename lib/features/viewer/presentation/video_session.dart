import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'seek_queue.dart';

/// The player behind one video page: the controller, its seeks, and a
/// replacement controller once the first has run to the end.
///
/// A player that reaches the end is spent. On the Pixel 9 Pro (video_player
/// 2.14.1, Media3 1.9.2) the plugin answers the end by pausing and seeking
/// to the duration, and ExoPlayer then stays in buffering: later seeks and
/// play are accepted and do nothing, so the last frame stays frozen. Rather
/// than ask that player for anything more, the next seek or play opens a
/// new one, moves it to the wanted position behind the old picture and
/// swaps it in.
class VideoSession extends ChangeNotifier {
  VideoSession(this._open);

  /// Makes an initialised controller with looping and volume already set.
  final Future<VideoPlayerController> Function() _open;

  VideoPlayerController? _c;
  SeekQueue? _seeks;
  Duration? _target;
  bool _spent = false;
  bool _playWhenRevived = false;
  double _speed = 1;
  Future<void>? _reviving;
  bool _disposed = false;

  /// Null until the first controller has opened.
  VideoPlayerController? get controller => _c;

  /// Where the last seek asked to go, until the player has caught up. Shown
  /// in place of the player's own position so the playhead stays under the
  /// finger.
  Duration? get target => _target;

  Duration get position => _target ?? _c?.value.position ?? Duration.zero;

  /// Completes once the seeks asked for so far have landed.
  Future<void> get settled => _reviving ?? _seeks?.idle ?? Future<void>.value();

  /// Opens the first controller. Throws what [_open] throws.
  Future<void> start() async {
    final VideoPlayerController c = await _open();
    if (_disposed) {
      await c.dispose();
      return;
    }
    _adopt(c);
  }

  void play() {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    if (_spent) {
      _playWhenRevived = true;
      _target ??= Duration.zero;
      notifyListeners();
      _revive();
      return;
    }
    c.play();
  }

  void pause() {
    _playWhenRevived = false;
    _c?.pause();
  }

  void seekTo(Duration position) {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    final Duration p = position < Duration.zero
        ? Duration.zero
        : (position > c.value.duration ? c.value.duration : position);
    _target = p;
    notifyListeners();
    if (_spent) {
      _revive();
      return;
    }
    _seeks!.request(p);
    _seeks!.idle.then((_) {
      if (_disposed || _spent) return;
      _target = null;
      notifyListeners();
    });
  }

  void setSpeed(double speed) {
    _speed = speed;
    _c?.setPlaybackSpeed(speed);
  }

  void _adopt(VideoPlayerController c) {
    c.addListener(_onValue);
    _c = c;
    _seeks = SeekQueue((Duration p) => _seekAndSettle(c, p));
    _spent = false;
    notifyListeners();
  }

  void _onValue() {
    final VideoPlayerValue v = _c!.value;
    // Latched: the plugin clears isCompleted again on the next seek.
    if (v.isCompleted && !v.isLooping) _spent = true;
    notifyListeners();
  }

  Future<void> _revive() => _reviving ??= _openReplacement();

  Future<void> _openReplacement() async {
    final VideoPlayerController old = _c!;
    final VideoPlayerController c;
    try {
      c = await _open();
    } on Exception {
      // Keep the old picture; the next seek or play tries again.
      _reviving = null;
      return;
    }
    if (_speed != 1 && !_disposed) await c.setPlaybackSpeed(_speed);
    // The target may move while each seek lands; stop at the newest.
    Duration at;
    do {
      if (_disposed) {
        await c.dispose();
        return;
      }
      at = _target ?? Duration.zero;
      await _seekAndSettle(c, at);
    } while (at != (_target ?? Duration.zero));
    if (_disposed) {
      await c.dispose();
      return;
    }
    old.removeListener(_onValue);
    _target = null;
    _reviving = null;
    _adopt(c);
    if (_playWhenRevived) {
      _playWhenRevived = false;
      c.play();
    }
    await old.dispose();
  }

  /// One seek, finished when the player has the frame ready.
  ///
  /// The plugin's own future completes as soon as the request is handed
  /// over. ExoPlayer goes to buffering on every seek and back to ready once
  /// the frame is decoded, which the plugin reports as isBuffering, so wait
  /// for that round trip. The timers cover a seek so quick that the change
  /// is never seen, and a player that never reports back.
  Future<void> _seekAndSettle(VideoPlayerController c, Duration p) async {
    await c.seekTo(p);
    if (_disposed) return;
    final Completer<void> done = Completer<void>();
    bool buffering = c.value.isBuffering;
    void listen() {
      if (c.value.isBuffering) {
        buffering = true;
      } else if (buffering && !done.isCompleted) {
        done.complete();
      }
    }

    c.addListener(listen);
    final Timer unseen = Timer(const Duration(milliseconds: 60), () {
      if (!buffering && !done.isCompleted) done.complete();
    });
    final Timer limit = Timer(const Duration(milliseconds: 500), () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    unseen.cancel();
    limit.cancel();
    c.removeListener(listen);
  }

  @override
  void dispose() {
    _disposed = true;
    _c?.removeListener(_onValue);
    _c?.dispose();
    super.dispose();
  }
}
