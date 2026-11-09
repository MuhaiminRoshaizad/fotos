import 'package:flutter/services.dart';

/// Camera details read from a photo's EXIF.
class CameraInfo {
  const CameraInfo({
    this.make,
    this.model,
    this.fNumber,
    this.exposure,
    this.iso,
    this.focalLength,
  });

  factory CameraInfo.fromMap(Map<Object?, Object?> m) => CameraInfo(
    make: m['make'] as String?,
    model: m['model'] as String?,
    fNumber: (m['fNumber'] as num?)?.toDouble(),
    exposure: (m['exposure'] as num?)?.toDouble(),
    iso: m['iso'] as int?,
    focalLength: (m['focalLength'] as num?)?.toDouble(),
  );

  final String? make;
  final String? model;
  final double? fNumber;
  final double? exposure;
  final int? iso;
  final double? focalLength;

  /// "Google Pixel 9 Pro" without repeating the make when the model has it.
  String? get camera {
    if (model == null) return make;
    if (make == null || model!.toLowerCase().startsWith(make!.toLowerCase())) {
      return model;
    }
    return '$make $model';
  }

  /// "f/1.7 · 1/120 s · ISO 64 · 6.9 mm", from whatever is present.
  String get settings {
    final List<String> parts = <String>[
      if (fNumber != null) 'f/${_trim(fNumber!)}',
      if (exposure != null)
        exposure! >= 1
            ? '${_trim(exposure!)} s'
            : '1/${(1 / exposure!).round()} s',
      if (iso != null) 'ISO $iso',
      if (focalLength != null) '${_trim(focalLength!)} mm',
    ];
    return parts.join(' · ');
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// A photo or video in Android's trash.
class TrashedItem {
  const TrashedItem({
    required this.id,
    required this.name,
    required this.video,
    required this.expires,
    required this.size,
    required this.width,
    required this.height,
    required this.duration,
  });

  factory TrashedItem.fromMap(Map<Object?, Object?> m) => TrashedItem(
    id: m['id']! as String,
    name: (m['name'] as String?) ?? '',
    video: m['video']! as bool,
    expires: DateTime.fromMillisecondsSinceEpoch(
      ((m['expires'] as num?) ?? 0).toInt() * 1000,
    ),
    size: ((m['size'] as num?) ?? 0).toInt(),
    width: ((m['width'] as num?) ?? 0).toInt(),
    height: ((m['height'] as num?) ?? 0).toInt(),
    duration: Duration(milliseconds: ((m['duration'] as num?) ?? 0).toInt()),
  );

  final String id;
  final String name;
  final bool video;

  /// When Android deletes it for good.
  final DateTime expires;
  final int size;
  final int width;
  final int height;
  final Duration duration;

  @override
  bool operator ==(Object other) => other is TrashedItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Dart side of the app's own Android channel (MainActivity / NativeChannel).
class NativeChannel {
  const NativeChannel();

  static const MethodChannel _channel = MethodChannel('my.minned.fotos/native');

  Future<List<TrashedItem>> trash() async {
    final List<Object?>? rows = await _channel.invokeMethod<List<Object?>>(
      'trashList',
    );
    return <TrashedItem>[
      for (final Object? r in rows ?? <Object?>[])
        TrashedItem.fromMap(r! as Map<Object?, Object?>),
    ];
  }

  Future<Uint8List?> trashThumbnail(TrashedItem item, int px) async {
    try {
      return await _channel.invokeMethod<Uint8List>(
        'trashThumbnail',
        <String, Object>{'id': item.id, 'video': item.video, 'px': px},
      );
    } on PlatformException {
      return null;
    }
  }

  Future<CameraInfo?> exif(String path) async {
    try {
      final Map<Object?, Object?>? m = await _channel
          .invokeMethod<Map<Object?, Object?>>('exif', <String, Object>{
            'path': path,
          });
      return m == null ? null : CameraInfo.fromMap(m);
    } on PlatformException {
      return null;
    }
  }
}
