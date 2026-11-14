import 'dart:async';

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

  // ---- MediaStore requests the user confirms once per batch -------------

  /// One system confirmation for the whole batch. True if the user agreed.
  Future<bool> favourite(
    List<String> ids,
    List<bool> videos, {
    required bool value,
  }) async =>
      (await _channel.invokeMethod<bool>('favourite', <String, Object>{
        'ids': ids,
        'videos': videos,
        'value': value,
      })) ??
      false;

  /// Moves to Android's trash, or back out with [value] false, in one
  /// request. Returns the ids that left (or came back to) the library,
  /// rows whose file was already gone included; empty if the user
  /// declined.
  Future<List<String>> setTrashed(
    List<String> ids,
    List<bool> videos, {
    required bool value,
  }) async =>
      (await _channel.invokeListMethod<String>('setTrashed', <String, Object>{
        'ids': ids,
        'videos': videos,
        'value': value,
      })) ??
      <String>[];

  /// Deletes for good, trashed items included. True if the user agreed.
  Future<bool> deleteForever(List<String> ids, List<bool> videos) async =>
      (await _channel.invokeMethod<bool>('deleteForever', <String, Object>{
        'ids': ids,
        'videos': videos,
      })) ??
      false;

  // ---- Files tab ----------------------------------------------------------

  Future<String> storageRoot() async =>
      (await _channel.invokeMethod<String>('root'))!;

  Future<bool> hasAllFilesAccess() async =>
      (await _channel.invokeMethod<bool>('hasAllFilesAccess')) ?? false;

  Future<void> openAllFilesAccessSettings() =>
      _channel.invokeMethod<void>('openAllFilesAccessSettings');

  Future<StorageStats> storage() async {
    final Map<Object?, Object?> m = (await _channel
        .invokeMethod<Map<Object?, Object?>>('storage'))!;
    return StorageStats(
      total: (m['total']! as num).toInt(),
      free: (m['free']! as num).toInt(),
    );
  }

  /// Updates MediaStore for files fotos changed, so the gallery tabs match.
  Future<void> scan(List<String> paths) =>
      _channel.invokeMethod<void>('scan', <String, Object>{'paths': paths});

  /// Returns false when no app can open the file.
  Future<bool> openWith(String path) async =>
      (await _channel.invokeMethod<bool>('openWith', <String, Object>{
        'path': path,
      })) ??
      false;

  Future<ZipInfo> zipInfo(String path) async {
    final Map<Object?, Object?> m = (await _channel
        .invokeMethod<Map<Object?, Object?>>('zipInfo', <String, Object>{
          'path': path,
        }))!;
    return ZipInfo(
      files: (m['files']! as num).toInt(),
      bytes: (m['bytes']! as num).toInt(),
      takeout: m['takeout']! as bool,
    );
  }

  static final StreamController<MethodCall> _events =
      StreamController<MethodCall>.broadcast();
  static bool _listening = false;

  /// Calls Android makes into Dart (progress reports), by method name.
  Stream<Object?> events(String method) {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((MethodCall call) async {
        _events.add(call);
      });
    }
    return _events.stream
        .where((MethodCall c) => c.method == method)
        .map((MethodCall c) => c.arguments);
  }

  /// For features that own their calls on this channel (the Takeout import).
  Future<T?> invoke<T>(String method, [Map<String, Object?>? args]) =>
      _channel.invokeMethod<T>(method, args);

  /// (done, total) while an extraction runs.
  Stream<(int, int)> get extractProgress =>
      events('extractProgress').map((Object? a) {
        final Map<Object?, Object?> m = a! as Map<Object?, Object?>;
        return (m['done']! as int, m['total']! as int);
      });

  /// Extracts [zip] into [target] and returns how many files were written.
  /// Throws [NotEnoughSpaceException] before writing anything when the phone
  /// lacks room.
  Future<int> extract(String zip, String target) async {
    try {
      return (await _channel.invokeMethod<int>('extract', <String, Object>{
        'zip': zip,
        'target': target,
      }))!;
    } on PlatformException catch (e) {
      final String msg = e.message ?? '';
      if (msg.startsWith('not_enough_space:')) {
        throw NotEnoughSpaceException(int.parse(msg.split(':').last));
      }
      rethrow;
    }
  }

  /// Completes when Android's own launch screen has finished and gone, with
  /// true when fotos was opened to show one photo and the flower should be
  /// skipped.
  Future<bool> awaitSplash() async =>
      await _channel.invokeMethod<bool>('awaitSplash') ?? false;

  /// Whether the image at [path] is a Motion Photo (a still with a short
  /// video appended to the same file).
  Future<bool> isMotionPhoto(String path) async =>
      await _channel.invokeMethod<bool>('isMotionPhoto', <String, Object>{
        'path': path,
      }) ??
      false;

  /// The video inside a Motion Photo, copied out to a file in the cache.
  /// Null when [path] is not one.
  Future<String?> motionVideo(String path) => _channel.invokeMethod<String>(
    'motionVideo',
    <String, Object>{'path': path},
  );

  /// A picture from inside a ZIP as JPEG bytes about [px] across (the
  /// first image by name), or null when it holds none.
  /// Points the home screen photo widgets that show or skip album [from]
  /// at [to], its id after a rename. Returns how many widgets changed.
  Future<int> rekeyWidgetAlbum(String from, String to) async =>
      await _channel.invokeMethod<int>('rekeyWidgetAlbum', <String, String>{
        'from': from,
        'to': to,
      }) ??
      0;

  Future<Uint8List?> zipCover(String path, int px) =>
      _channel.invokeMethod<Uint8List>('zipCover', <String, Object>{
        'path': path,
        'px': px,
      });

  /// How many pages the ZIP at [path] holds when it reads as a comic (all
  /// pictures but a few extras), or null when it doesn't.
  Future<int?> zipPageCount(String path) => _channel.invokeMethod<int>(
    'zipPageCount',
    <String, Object>{'path': path},
  );

  /// The files inside the ZIP at [path], in the order the archive lists them.
  Future<List<ZipEntry>> zipEntries(String path) async {
    final List<Object?> list = (await _channel.invokeMethod<List<Object?>>(
      'zipEntries',
      <String, Object>{'path': path},
    ))!;
    return <ZipEntry>[
      for (final Object? e in list)
        ZipEntry.fromMap((e! as Map<Object?, Object?>)),
    ];
  }

  /// A thumbnail for the entry [name] inside the ZIP at [path], about [px]
  /// across, or null when it is not an image Android can decode.
  Future<Uint8List?> zipPageThumb(String path, String name, int px) =>
      _channel.invokeMethod<Uint8List>('zipPageThumb', <String, Object>{
        'path': path,
        'name': name,
        'px': px,
      });

  /// (done, total) while a ZIP is being rewritten.
  Stream<(int, int)> get zipRemoveProgress =>
      events('zipRemoveProgress').map((Object? a) {
        final Map<Object?, Object?> m = a! as Map<Object?, Object?>;
        return (m['done']! as int, m['total']! as int);
      });

  /// Removes [names] from the ZIP at [path], rewriting it in place, and returns
  /// how many files remain inside. Throws [NotEnoughSpaceException] before
  /// touching the archive when the phone lacks room for the rewrite.
  Future<int> zipRemove(String path, List<String> names) async {
    try {
      return (await _channel.invokeMethod<int>('zipRemove', <String, Object>{
        'path': path,
        'names': names,
      }))!;
    } on PlatformException catch (e) {
      final String msg = e.message ?? '';
      if (msg.startsWith('not_enough_space:')) {
        throw NotEnoughSpaceException(int.parse(msg.split(':').last));
      }
      rethrow;
    }
  }

  /// A frame from a video file as JPEG bytes about [px] across, or null
  /// when Android cannot read one.
  Future<Uint8List?> videoFrame(String path, int px) =>
      _channel.invokeMethod<Uint8List>('videoFrame', <String, Object>{
        'path': path,
        'px': px,
      });

  /// A picture or video file's thumbnail as JPEG bytes about [px] across,
  /// from Android's own thumbnail store where it knows the file, or null.
  Future<Uint8List?> thumbnail(String path, int px) =>
      _channel.invokeMethod<Uint8List>('thumbnail', <String, Object>{
        'path': path,
        'px': px,
      });

  /// [count] frames spread evenly through a video file, each JPEG bytes
  /// about [px] across, null where Android cannot read one. Taken in one
  /// pass from the keyframes nearest each slot.
  Future<List<Uint8List?>> videoFrames(String path, int count, int px) async {
    final List<Object?>? frames = await _channel.invokeListMethod<Object?>(
      'videoFrames',
      <String, Object>{'path': path, 'count': count, 'px': px},
    );
    return <Uint8List?>[
      for (final Object? f in frames ?? const <Object?>[]) f as Uint8List?,
    ];
  }

  Future<int> pdfPageCount(String path) async => (await _channel
      .invokeMethod<int>('pdfPageCount', <String, Object>{'path': path}))!;

  Future<Uint8List> pdfPage(String path, int index, int width) async =>
      (await _channel.invokeMethod<Uint8List>('pdfPage', <String, Object>{
        'path': path,
        'index': index,
        'width': width,
      }))!;

  Future<void> keepScreenOn(bool on) =>
      _channel.invokeMethod<void>('keepScreenOn', <String, Object>{'on': on});
}

class StorageStats {
  const StorageStats({required this.total, required this.free});
  final int total;
  final int free;
  int get used => total - free;
}

class ZipInfo {
  const ZipInfo({
    required this.files,
    required this.bytes,
    required this.takeout,
  });

  final int files;

  /// Total size once extracted.
  final int bytes;

  /// Looks like a Google Takeout archive.
  final bool takeout;
}

/// One file inside a ZIP, as the contents screen lists it.
class ZipEntry {
  const ZipEntry({
    required this.name,
    required this.size,
    required this.isImage,
  });

  /// The full entry name, which may include folders (e.g. "chapter 1/001.jpg").
  final String name;
  final int size;

  /// Whether Android can likely decode it as a page thumbnail.
  final bool isImage;

  factory ZipEntry.fromMap(Map<Object?, Object?> m) => ZipEntry(
    name: m['name']! as String,
    size: (m['size']! as num).toInt(),
    isImage: m['isImage']! as bool,
  );
}

class NotEnoughSpaceException implements Exception {
  const NotEnoughSpaceException(this.needed);
  final int needed;
}
