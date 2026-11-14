import 'dart:async';

/// Sends seeks to a video player one at a time, always to the newest target.
///
/// A drag produces a seek per pointer event. The player does every one of
/// them in turn, each an exact seek that decodes from the previous keyframe,
/// so they pile up and playback only resumes once the pile is cleared. Here
/// a seek that arrives while another is under way replaces whatever was
/// waiting, so the player is never more than one seek behind the finger.
class SeekQueue {
  SeekQueue(this._seek);

  /// Performs one seek and completes when the player has shown its frame.
  final Future<void> Function(Duration position) _seek;

  Duration? _next;
  Future<void>? _running;

  /// Completes when every requested seek has been carried out.
  Future<void> get idle => _running ?? Future<void>.value();

  void request(Duration position) {
    _next = position;
    _running ??= _run();
  }

  Future<void> _run() async {
    while (_next != null) {
      final Duration target = _next!;
      _next = null;
      await _seek(target);
    }
    _running = null;
  }
}
