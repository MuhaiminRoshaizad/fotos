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

/// Dart side of the app's own Android channel (MainActivity / NativeChannel).
class NativeChannel {
  const NativeChannel();

  static const MethodChannel _channel = MethodChannel('my.minned.fotos/native');

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
