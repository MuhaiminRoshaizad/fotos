import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Reads frames at given moments (ms), in one batch.
typedef FrameReader = Future<List<Uint8List?>> Function(List<int> times);

/// Frames for the editor's timeline, kept while the editor is open.
///
/// The strip asks for the moments it is showing; they are read a batch at a
/// time, newest request first, so a fast scroll never queues up frames for
/// places already left behind. A moment not read yet shows the nearest frame
/// that has been, so the strip is never blank while frames arrive.
class TimelineFrames extends ChangeNotifier {
  TimelineFrames(this._read);

  final FrameReader _read;
  final SplayTreeMap<int, Uint8List> _frames = SplayTreeMap<int, Uint8List>();
  final Set<int> _failed = <int>{};
  List<int> _wanted = const <int>[];
  bool _reading = false;
  bool _disposed = false;

  /// At most this many frames per trip to Android.
  static const int batch = 8;

  /// At most this many frames kept; past it, those farthest from the
  /// stretch last shown go first. Scrolling a zoomed-in hour asks for
  /// thousands.
  static const int keep = 400;
  int _near = 0;

  /// The frame for [ms], or the nearest one read so far.
  Uint8List? frameNear(int ms) {
    final Uint8List? exact = _frames[ms];
    if (exact != null) return exact;
    final int? below = _frames.lastKeyBefore(ms);
    final int? above = _frames.firstKeyAfter(ms);
    if (below == null) return above == null ? null : _frames[above];
    if (above == null) return _frames[below];
    return _frames[(ms - below) <= (above - ms) ? below : above];
  }

  bool has(int ms) => _frames.containsKey(ms);

  /// The moments on screen now; replaces what was asked for before.
  void want(List<int> times) {
    if (times.isNotEmpty) _near = times[times.length ~/ 2];
    _wanted = <int>[
      for (final int t in times)
        if (!_frames.containsKey(t) && !_failed.contains(t)) t,
    ];
    _pump();
  }

  Future<void> _pump() async {
    if (_reading || _wanted.isEmpty || _disposed) return;
    _reading = true;
    final List<int> next = _wanted.take(batch).toList();
    _wanted = _wanted.skip(batch).toList();
    try {
      final List<Uint8List?> got = await _read(next);
      if (_disposed) return;
      for (int i = 0; i < next.length; i++) {
        final Uint8List? f = i < got.length ? got[i] : null;
        if (f == null) {
          _failed.add(next[i]);
        } else {
          _frames[next[i]] = f;
        }
      }
      _trim();
      notifyListeners();
    } on Object {
      _failed.addAll(next);
    } finally {
      _reading = false;
    }
    _pump();
  }

  void _trim() {
    while (_frames.length > keep) {
      final int first = _frames.firstKey()!;
      final int last = _frames.lastKey()!;
      _frames.remove(
        (_near - first).abs() > (last - _near).abs() ? first : last,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
