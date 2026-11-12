import 'package:photo_manager/photo_manager.dart';

/// Whether [e] may hold more than one frame: a GIF or WebP picture, as in
/// comics with moving pages. Android's previews are stills, so such a
/// picture is shown from its original file to keep it moving.
bool mayAnimate(AssetEntity e) {
  if (e.type != AssetType.image) return false;
  final String mime = (e.mimeType ?? '').toLowerCase();
  final String name = (e.title ?? '').toLowerCase();
  return mime == 'image/gif' ||
      mime == 'image/webp' ||
      name.endsWith('.gif') ||
      name.endsWith('.webp');
}
