import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../../albums/presentation/albums_providers.dart';
import '../../../core/widgets/viewer_glass.dart';

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

/// The id of the Motion Photo whose video is on screen now, for its badge
/// to show.
class MotionPlayingNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final motionPlayingProvider = NotifierProvider<MotionPlayingNotifier, String?>(
  MotionPlayingNotifier.new,
);

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
    ref.read(motionPlayingProvider.notifier).set(widget.asset.id);
    await c.play();
  }

  void _stop() {
    _held = false;
    if (_c == null) return;
    ref.read(motionPlayingProvider.notifier).set(null);
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

/// The mark on a Motion Photo in the viewer, under the top bar. While the
/// photo's video plays, rings spread from the glyph, the way ripples leave
/// a point: the picture is moving.
class MotionBadge extends ConsumerWidget {
  const MotionBadge({super.key, required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool motion = ref.watch(isMotionPhotoProvider(asset)).value ?? false;
    if (!motion) return const SizedBox.shrink();
    final bool playing = ref.watch(motionPlayingProvider) == asset.id;
    return Semantics(
      label: playing
          ? 'Motion Photo, playing.'
          : 'Motion Photo. Press and hold the photo to play it.',
      excludeSemantics: true,
      child: ViewerGlass(
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Ripple(active: playing),
              const SizedBox(width: 6),
              const Text(
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

/// The badge's glyph, with two rings that grow and fade in turn while
/// [active]. Still when animations are turned off.
class _Ripple extends StatefulWidget {
  const _Ripple({required this.active});
  final bool active;

  @override
  State<_Ripple> createState() => _RippleState();
}

class _RippleState extends State<_Ripple> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Ripple old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final bool run = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? glyph) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          if (_c.isAnimating)
            for (final double phase in const <double>[0, 0.5])
              _ring((_c.value + phase) % 1),
          glyph!,
        ],
      ),
      child: Icon(
        widget.active
            ? CupertinoIcons.smallcircle_fill_circle
            : CupertinoIcons.smallcircle_circle,
        size: 16,
        color: Colors.white,
      ),
    ),
  );

  Widget _ring(double t) => Transform.scale(
    scale: 1 + 0.9 * t,
    child: Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.7 * (1 - t)),
          width: 1.2,
        ),
      ),
    ),
  );
}
