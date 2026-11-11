import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../../albums/presentation/albums_providers.dart';
import 'viewer_glass.dart';

/// Whether the photo with this id is a Motion Photo: a still with a short
/// video inside the same file. Checked once per photo, by reading the
/// file's header natively.
final isMotionPhotoProvider = FutureProvider.family<bool, AssetEntity>((
  Ref ref,
  AssetEntity asset,
) async {
  if (asset.type != AssetType.image) return false;
  // The original, not a converted copy: the video is appended to it.
  final File? file = await asset.originFile;
  if (file == null) return false;
  return ref.watch(nativeChannelProvider).isMotionPhoto(file.path);
});

/// A photo in the viewer that plays its motion while it is held, as iOS
/// plays a Live Photo: press and hold, the video fades in over the still
/// and plays; let go and the still returns. A plain photo is drawn as it
/// is and holding it does nothing.
class MotionPhoto extends ConsumerStatefulWidget {
  const MotionPhoto({super.key, required this.asset, required this.child});

  final AssetEntity asset;
  final Widget child;

  @override
  ConsumerState<MotionPhoto> createState() => _MotionPhotoState();
}

class _MotionPhotoState extends ConsumerState<MotionPhoto> {
  VideoPlayerController? _c;
  bool _held = false;
  bool _showing = false;

  Future<void> _start() async {
    _held = true;
    AppHaptics.light();
    final File? file = await widget.asset.originFile;
    if (file == null || !mounted || !_held) return;
    final String? video = await ref
        .read(nativeChannelProvider)
        .motionVideo(file.path);
    if (video == null || !mounted || !_held) return;
    final VideoPlayerController c = VideoPlayerController.file(File(video));
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
    } on Object {
      await c.dispose();
      return;
    }
    if (!mounted || !_held) {
      await c.dispose();
      return;
    }
    setState(() {
      _c = c;
      _showing = true;
    });
    await c.play();
  }

  void _stop() {
    _held = false;
    if (_c == null) return;
    // Fade back to the still, then let the player go.
    setState(() => _showing = false);
    final VideoPlayerController c = _c!;
    Future<void>.delayed(AppMotion.medium, () {
      if (mounted && _c == c && !_showing) setState(() => _c = null);
      c.dispose();
    });
  }

  @override
  void dispose() {
    _held = false;
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool motion =
        ref.watch(isMotionPhotoProvider(widget.asset)).value ?? false;
    if (!motion) return widget.child;
    final VideoPlayerController? c = _c;
    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          widget.child,
          if (c != null)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showing ? 1 : 0,
                duration: AppMotion.medium,
                curve: Curves.easeOut,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The mark on a Motion Photo in the viewer, under the top bar.
class MotionBadge extends ConsumerWidget {
  const MotionBadge({super.key, required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool motion = ref.watch(isMotionPhotoProvider(asset)).value ?? false;
    if (!motion) return const SizedBox.shrink();
    return Semantics(
      label: 'Motion Photo. Press and hold the photo to play it.',
      excludeSemantics: true,
      child: const ViewerGlass(
        shape: StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                CupertinoIcons.smallcircle_circle,
                size: 16,
                color: Colors.white,
              ),
              SizedBox(width: 6),
              Text(
                'MOTION',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
