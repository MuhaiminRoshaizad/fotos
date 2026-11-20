import 'dart:io';
import 'dart:typed_data';

/// The length of an MP4 file, read from its boxes.
///
/// Android's media scanner takes a video's length from the file's header
/// (`mvhd`). A fragmented MP4, as screen and game recorders write, leaves
/// that at 0 and keeps its samples in fragments (`moof`) after it, so
/// Android lists the video as 0:00 long. This reads the fragments' sample
/// durations instead: only box headers and the small `moov` and `moof`
/// boxes are read, never the media data.
///
/// Null when [file] is not an MP4 or holds no length anywhere.
Future<Duration?> mp4Length(RandomAccessFile file) async {
  final _Mp4 mp4 = _Mp4();
  final int size = await file.length();
  int at = 0;
  while (at + 8 <= size) {
    await file.setPosition(at);
    final ByteData head = ByteData.sublistView(await file.read(16));
    if (head.lengthInBytes < 8) break;
    int length = head.getUint32(0);
    final String type = _type(head, 4);
    int header = 8;
    if (length == 1) {
      if (head.lengthInBytes < 16) break;
      length = head.getUint64(8);
      header = 16;
    } else if (length == 0) {
      length = size - at;
    }
    if (length < header || at + length > size) break;
    if ((type == 'moov' || type == 'moof') && length <= _largestBox) {
      await file.setPosition(at + header);
      final ByteData body = ByteData.sublistView(
        await file.read(length - header),
      );
      try {
        type == 'moov' ? mp4.moov(body) : mp4.moof(body);
      } on RangeError {
        // A box cut short: what was read before it still counts.
      }
    }
    at += length;
  }
  return mp4.length;
}

/// A header box is a few kilobytes; anything far larger is not one.
const int _largestBox = 16 << 20;

String _type(ByteData b, int at) =>
    String.fromCharCodes(b.buffer.asUint8List(b.offsetInBytes + at, 4));

/// The boxes directly inside [b] from [start] to [end]: type, where the
/// body starts and where the box ends.
Iterable<(String, int, int)> _children(ByteData b, int start, int end) sync* {
  int at = start;
  while (at + 8 <= end) {
    int length = b.getUint32(at);
    int header = 8;
    if (length == 1) {
      if (at + 16 > end) return;
      length = b.getUint64(at + 8);
      header = 16;
    } else if (length == 0) {
      length = end - at;
    }
    if (length < header || at + length > end) return;
    yield (_type(b, at + 4), at + header, at + length);
    at += length;
  }
}

class _Mp4 {
  int _movieScale = 0;
  int _movieLength = 0;

  /// The `mehd` box: the whole fragmented movie's length, when written.
  int _fragmentedLength = 0;

  final Map<int, int> _scale = <int, int>{};
  final Map<int, int> _defaultDuration = <int, int>{};

  /// Where each track's samples end so far, in its own timescale.
  final Map<int, int> _end = <int, int>{};

  Duration? get length {
    if (_movieScale > 0 && _movieLength > 0) {
      return _time(_movieLength, _movieScale);
    }
    if (_movieScale > 0 && _fragmentedLength > 0) {
      return _time(_fragmentedLength, _movieScale);
    }
    Duration? longest;
    for (final MapEntry<int, int> e in _end.entries) {
      final int scale = _scale[e.key] ?? 0;
      if (scale <= 0) continue;
      final Duration d = _time(e.value, scale);
      if (longest == null || d > longest) longest = d;
    }
    return longest;
  }

  static Duration _time(int units, int scale) =>
      Duration(microseconds: units * 1000000 ~/ scale);

  void moov(ByteData b) {
    for (final (String type, int s, int e) in _children(
      b,
      0,
      b.lengthInBytes,
    )) {
      switch (type) {
        case 'mvhd':
          final (int scale, int length) = _scaleAndLength(b, s);
          _movieScale = scale;
          _movieLength = length;
        case 'trak':
          _trak(b, s, e);
        case 'mvex':
          for (final (String t, int cs, int _) in _children(b, s, e)) {
            if (t == 'mehd') {
              _fragmentedLength = b.getUint8(cs) == 1
                  ? b.getUint64(cs + 4)
                  : b.getUint32(cs + 4);
            } else if (t == 'trex') {
              _defaultDuration[b.getUint32(cs + 4)] = b.getUint32(cs + 12);
            }
          }
      }
    }
  }

  /// The timescale and length of an `mvhd` or `mdhd` box.
  static (int, int) _scaleAndLength(ByteData b, int s) => b.getUint8(s) == 1
      ? (b.getUint32(s + 20), b.getUint64(s + 24))
      : (b.getUint32(s + 12), b.getUint32(s + 16));

  void _trak(ByteData b, int s, int e) {
    int? track;
    int scale = 0;
    for (final (String type, int cs, int ce) in _children(b, s, e)) {
      if (type == 'tkhd') {
        track = b.getUint32(cs + (b.getUint8(cs) == 1 ? 20 : 12));
      } else if (type == 'mdia') {
        for (final (String t, int ms, int _) in _children(b, cs, ce)) {
          if (t == 'mdhd') scale = _scaleAndLength(b, ms).$1;
        }
      }
    }
    if (track != null) _scale[track] = scale;
  }

  void moof(ByteData b) {
    for (final (String type, int s, int e) in _children(
      b,
      0,
      b.lengthInBytes,
    )) {
      if (type == 'traf') _traf(b, s, e);
    }
  }

  void _traf(ByteData b, int s, int e) {
    int? track;
    int? perSample;
    int? start;
    int total = 0;
    for (final (String type, int cs, int _) in _children(b, s, e)) {
      final int flags = b.getUint32(cs) & 0xFFFFFF;
      switch (type) {
        case 'tfhd':
          track = b.getUint32(cs + 4);
          int at = cs + 8;
          if (flags & 0x01 != 0) at += 8; // base data offset
          if (flags & 0x02 != 0) at += 4; // sample description index
          if (flags & 0x08 != 0) perSample = b.getUint32(at);
        case 'tfdt':
          start = b.getUint8(cs) == 1
              ? b.getUint64(cs + 4)
              : b.getUint32(cs + 4);
        case 'trun':
          final int count = b.getUint32(cs + 4);
          int at = cs + 8;
          if (flags & 0x01 != 0) at += 4; // data offset
          if (flags & 0x04 != 0) at += 4; // first sample flags
          final int each =
              (flags & 0x100 != 0 ? 4 : 0) +
              (flags & 0x200 != 0 ? 4 : 0) +
              (flags & 0x400 != 0 ? 4 : 0) +
              (flags & 0x800 != 0 ? 4 : 0);
          if (flags & 0x100 == 0) {
            // All alike; the count is not trusted to bound a loop.
            total += count * (perSample ?? _defaultDuration[track] ?? 0);
          } else {
            // A count larger than the box ends in a RangeError.
            for (int i = 0; i < count; i++) {
              total += b.getUint32(at + i * each);
            }
          }
      }
    }
    if (track == null) return;
    final int end = (start ?? _end[track] ?? 0) + total;
    if (end > (_end[track] ?? 0)) _end[track] = end;
  }
}
