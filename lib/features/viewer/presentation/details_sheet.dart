import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/video_length.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/inset_group.dart';

/// Date, file, camera and place for one photo or video.
class DetailsSheet extends StatefulWidget {
  const DetailsSheet({super.key, required this.asset});

  final AssetEntity asset;

  @override
  State<DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<DetailsSheet> {
  late final Future<_Extra> _extra = _load();

  Future<_Extra> _load() async {
    final AssetEntity a = widget.asset;
    final int size = await a.fileSize;
    final LatLng? where = await a.latlngAsync();
    CameraInfo? camera;
    if (a.type == AssetType.image) {
      final File? f = await a.originFile;
      if (f != null) camera = await const NativeChannel().exif(f.path);
    }
    final Duration? length = a.type == AssetType.video && a.duration == 0
        ? await readVideoLength(a)
        : null;
    return _Extra(size: size, where: where, camera: camera, length: length);
  }

  @override
  Widget build(BuildContext context) {
    final AssetEntity a = widget.asset;
    final DateTime d = a.createDateTime;
    final bool video = a.type == AssetType.video;
    return FutureBuilder<_Extra>(
      future: _extra,
      builder: (BuildContext context, AsyncSnapshot<_Extra> snap) {
        final _Extra? x = snap.data;
        final LatLng? where = x?.where;
        final bool hasPlace =
            where != null && (where.latitude != 0 || where.longitude != 0);
        final String? camera = x?.camera?.camera;
        // Android lists a fragmented MP4 as 0:00; its length comes with
        // the rest, read from the file.
        final Duration? length = a.duration > 0 ? a.videoDuration : x?.length;
        final String dims =
            '${a.orientatedWidth} × ${a.orientatedHeight}'
            '${video && length != null ? ' · ${Fmt.duration(length)}' : ''}';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SheetTitle(Fmt.dayHeading(d), subtitle: Fmt.time(d)),
            InsetGroup(
              children: <Widget>[
                _Row(
                  icon: video ? CupertinoIcons.videocam : CupertinoIcons.photo,
                  title: a.title ?? 'Untitled',
                  subtitle: x == null ? dims : '${Fmt.size(x.size)} · $dims',
                ),
                if (camera != null)
                  _Row(
                    icon: CupertinoIcons.camera,
                    title: camera,
                    subtitle: x!.camera!.settings,
                  ),
              ],
            ),
            if (hasPlace || a.relativePath != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              InsetGroup(
                children: <Widget>[
                  if (hasPlace)
                    _Row(
                      icon: CupertinoIcons.location,
                      title:
                          '${where.latitude.toStringAsFixed(5)}, '
                          '${where.longitude.toStringAsFixed(5)}',
                      subtitle: 'Where it was taken',
                    ),
                  if (a.relativePath != null)
                    _Row(
                      icon: CupertinoIcons.folder,
                      title: a.relativePath!.replaceAll(RegExp(r'/$'), ''),
                      subtitle: 'Folder',
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

class _Extra {
  const _Extra({required this.size, this.where, this.camera, this.length});
  final int size;
  final LatLng? where;
  final CameraInfo? camera;

  /// A video's length when Android lists it as 0:00.
  final Duration? length;
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return GroupRow(
      leading: Icon(icon),
      title: title,
      subtitle: subtitle == null || subtitle!.isEmpty ? null : subtitle,
    );
  }
}
