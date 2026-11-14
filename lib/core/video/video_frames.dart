import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/albums/presentation/albums_providers.dart'
    show nativeChannelProvider;
import '../platform/native_channel.dart';

/// A picture from a video: the moment it shows (ms) and JPEG bytes.
typedef VideoFrame = ({int ms, Uint8List jpeg});

/// A stretch of a video a strip tile stands for, in ms: [from] up to, not
/// including, [until].
typedef Stretch = ({int from, int until});

/// Reads pictures from one video file.
abstract interface class FrameSource {
  /// A picture from inside [from] to [until], or null.
  Future<VideoFrame?> frameIn(int from, int until);

  /// Lets go of the file; a later [frameIn] opens it again.
  void close();
}

/// Frames for the viewer's strip and the editor's timeline, shared by both.
///
/// Each tile asks for a picture from inside its own stretch of the video,
/// and shows one as soon as it is read: nothing waits for its neighbours,
/// and no tile borrows a picture from outside its stretch. Tiles nearest
/// the playhead are read first. A tile shows the earliest picture read
/// inside its stretch, so when the editor's tiles split in two on zooming
/// in, every picture already showing stays where it is.
class VideoFrames extends ChangeNotifier {
  VideoFrames(this._source, {this.idleAfter = const Duration(seconds: 10)});

  final FrameSource _source;

  /// How long the file stays open after the last read, for the next
  /// scroll or zoom.
  final Duration idleAfter;

  /// Reads at a time, one per reader Android keeps open.
  static const int readers = 3;

  /// At most this many pictures kept; past it, those farthest from the
  /// playhead go first. Scrolling a zoomed-in hour asks for thousands.
  static const int keep = 400;

  final SplayTreeMap<int, Uint8List> _frames = SplayTreeMap<int, Uint8List>();
  final Set<int> _failed = <int>{};
  final Set<int> _reading = <int>{};
  List<Stretch> _wanted = const <Stretch>[];
  int _focus = 0;
  Timer? _idle;
  bool _disposed = false;

  /// The earliest picture read from inside [from] to [until], or null.
  Uint8List? frameIn(int from, int until) {
    final int? at = _frames.containsKey(from)
        ? from
        : _frames.firstKeyAfter(from);
    return at != null && at < until ? _frames[at] : null;
  }

  /// Whether a picture for [from] to [until] may still come.
  bool loading(int from, int until) =>
      frameIn(from, until) == null && !_failed.contains(from);

  /// The stretches on screen now, replacing those asked for before; read
  /// nearest [focus] first.
  void want(List<Stretch> stretches, {required int focus}) {
    if (_disposed) return;
    _focus = focus;
    _wanted = <Stretch>[
      for (final Stretch s in stretches)
        if (loading(s.from, s.until)) s,
    ];
    _pump();
  }

  void _pump() {
    while (_reading.length < readers) {
      final Stretch? next = _nearest();
      if (next == null) break;
      _wanted.remove(next);
      _read(next);
    }
    _idle?.cancel();
    _idle = _reading.isEmpty ? Timer(idleAfter, _source.close) : null;
  }

  Stretch? _nearest() {
    Stretch? best;
    int bestGap = 0;
    for (final Stretch s in _wanted) {
      if (_reading.contains(s.from) || !loading(s.from, s.until)) continue;
      final int gap = _focus < s.from
          ? s.from - _focus
          : _focus >= s.until
          ? _focus - s.until + 1
          : 0;
      if (best == null || gap < bestGap) {
        best = s;
        bestGap = gap;
      }
    }
    return best;
  }

  Future<void> _read(Stretch s) async {
    _reading.add(s.from);
    VideoFrame? f;
    try {
      f = await _source.frameIn(s.from, s.until);
    } on Object {
      f = null;
    }
    _reading.remove(s.from);
    if (_disposed) return;
    if (f == null) {
      _failed.add(s.from);
    } else {
      _frames[f.ms] = f.jpeg;
      _trim();
    }
    notifyListeners();
    _pump();
  }

  void _trim() {
    while (_frames.length > keep) {
      final int first = _frames.firstKey()!;
      final int last = _frames.lastKey()!;
      _frames.remove(
        (_focus - first).abs() > (last - _focus).abs() ? first : last,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _idle?.cancel();
    _source.close();
    super.dispose();
  }
}

/// [FrameSource] over Android's frame readers, opened on first use.
class NativeFrameSource implements FrameSource {
  NativeFrameSource(this._native, this._path, this._px);

  final NativeChannel _native;
  final String _path;
  final int _px;
  Future<int>? _id;

  @override
  Future<VideoFrame?> frameIn(int from, int until) async {
    final int id = await (_id ??= _native.videoFramesOpen(_path, _px));
    return _native.videoFrameIn(id, from, until);
  }

  @override
  void close() {
    final Future<int>? id = _id;
    _id = null;
    id?.then(_native.videoFramesClose, onError: (Object _) {});
  }
}

/// The frames of the video file at a path, shared by its viewer page and
/// its editor. Kept two minutes after both close, so going back to a video
/// shows its strip at once.
final videoFramesProvider = Provider.autoDispose.family<VideoFrames, String>((
  Ref ref,
  String path,
) {
  final VideoFrames frames = VideoFrames(
    NativeFrameSource(ref.watch(nativeChannelProvider), path, 192),
  );
  final link = ref.keepAlive();
  Timer? expiry;
  ref.onCancel(() => expiry = Timer(const Duration(minutes: 2), link.close));
  ref.onResume(() => expiry?.cancel());
  ref.onDispose(() {
    expiry?.cancel();
    frames.dispose();
  });
  return frames;
});
