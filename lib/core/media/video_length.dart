import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../format/formatters.dart';
import '../video/mp4_length.dart';

/// A video's length. Android lists a fragmented MP4 (from screen and game
/// recorders) as 0 seconds long, so for those it is read from the file; see
/// [mp4Length]. Zero when the file can't tell either.
final videoLengthProvider = FutureProvider.family<Duration, AssetEntity>(
  (Ref ref, AssetEntity asset) => readVideoLength(asset),
);

/// [asset]'s length, from Android or else from the file; see
/// [videoLengthProvider].
Future<Duration> readVideoLength(AssetEntity asset) async {
  if (asset.duration > 0) return asset.videoDuration;
  RandomAccessFile? file;
  try {
    final File? f = await asset.originFile;
    if (f == null) return Duration.zero;
    file = await f.open();
    return await mp4Length(file) ?? Duration.zero;
  } on FileSystemException {
    return Duration.zero;
  } finally {
    await file?.close();
  }
}

/// [asset]'s length as a clock ("0:14"). Android's own figure shows at once;
/// one it lists as 0:00 shows once the file has been read, blank until then.
class VideoLengthText extends ConsumerWidget {
  const VideoLengthText(this.asset, {super.key, required this.builder});

  final AssetEntity asset;
  final Widget Function(BuildContext context, String length) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (asset.duration > 0) {
      return builder(context, Fmt.duration(asset.videoDuration));
    }
    final Duration? d = ref.watch(videoLengthProvider(asset)).value;
    return builder(context, d == null ? '' : Fmt.duration(d));
  }
}
