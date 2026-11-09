import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/viewer_settings.dart';

/// One video in the viewer.
///
/// Double-tap the left or right third to skip 10 s (taps that follow quickly
/// keep adding), double-tap the middle to play or pause, press and hold for
/// 2x speed, and drag the filmstrip to scrub.
class VideoPage extends ConsumerStatefulWidget {
  const VideoPage({
    super.key,
    required this.asset,
    required this.active,
    required this.chrome,
    required this.onTap,
  });

  final AssetEntity asset;

  /// Only the page on screen plays.
  final bool active;
  final bool chrome;
  final VoidCallback onTap;

  @override
  ConsumerState<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends ConsumerState<VideoPage> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _fast = false;
  bool _scrubbing = false;
  bool _wasPlaying = false;
  int _streakSide = 0;
  int _streakCount = 0;
  DateTime _streakAt = DateTime(0);
  Timer? _seekBadge;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final File? f = await widget.asset.file;
    if (!mounted) return;
    if (f == null) {
      setState(() => _failed = true);
      return;
    }
    final VideoPlayerController c = VideoPlayerController.file(f);
    try {
      await c.initialize();
    } on Exception {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    final ViewerSettings s =
        ref.read(viewerSettingsProvider).value ?? const ViewerSettings();
    await c.setLooping(s.loop);
    await c.setVolume(s.muted ? 0 : 1);
    c.addListener(_tick);
    setState(() => _c = c);
    if (widget.active) c.play();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(VideoPage old) {
    super.didUpdateWidget(old);
    final VideoPlayerController? c = _c;
    if (c == null || old.active == widget.active) return;
    widget.active ? c.play() : c.pause();
  }

  @override
  void dispose() {
    _seekBadge?.cancel();
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  int _side(double x, double width) {
    if (x < width * 0.38) return -1;
    if (x > width * 0.62) return 1;
    return 0;
  }

  void _seek(int side) {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    final DateTime now = DateTime.now();
    if (side != _streakSide || now.difference(_streakAt).inMilliseconds > 700) {
      _streakCount = 0;
    }
    _streakSide = side;
    _streakCount++;
    _streakAt = now;
    final Duration target = c.value.position + Duration(seconds: 10 * side);
    c.seekTo(
      target < Duration.zero
          ? Duration.zero
          : (target > c.value.duration ? c.value.duration : target),
    );
    AppHaptics.light();
    _seekBadge?.cancel();
    _seekBadge = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _streakSide = 0);
    });
    setState(() {});
  }

  void _togglePlay() {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _c;
    if (_failed) {
      return const Center(
        child: Text(
          'This video can\'t be played.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    final Widget picture = c == null
        ? Image(
            image: AssetEntityImageProvider(
              widget.asset,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(1024),
            ),
            fit: BoxFit.contain,
          )
        : AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c));

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails d) {
            final int side = _side(d.localPosition.dx, box.maxWidth);
            final bool streak =
                side != 0 &&
                side == _streakSide &&
                DateTime.now().difference(_streakAt).inMilliseconds < 700;
            streak ? _seek(side) : widget.onTap();
          },
          onDoubleTapDown: (TapDownDetails d) {
            final int side = _side(d.localPosition.dx, box.maxWidth);
            side == 0 ? _togglePlay() : _seek(side);
          },
          onDoubleTap: () {},
          onLongPressStart: (_) {
            if (c == null) return;
            _wasPlaying = c.value.isPlaying;
            c.setPlaybackSpeed(2);
            c.play();
            AppHaptics.light();
            setState(() => _fast = true);
          },
          onLongPressEnd: (_) {
            if (c == null) return;
            c.setPlaybackSpeed(1);
            if (!_wasPlaying) c.pause();
            setState(() => _fast = false);
          },
          child: Stack(
            children: <Widget>[
              Center(child: picture),
              if (_streakSide != 0)
                _SeekBadge(side: _streakSide, count: _streakCount),
              if (_fast)
                const Positioned(
                  top: 96,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _Pill(
                      text: '2× speed',
                      icon: Icons.fast_forward_rounded,
                    ),
                  ),
                ),
              if (c != null &&
                  !c.value.isPlaying &&
                  !_scrubbing &&
                  widget.chrome)
                Center(
                  child: IconButton.filled(
                    tooltip: 'Play',
                    iconSize: 36,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(72, 72),
                    ),
                    onPressed: _togglePlay,
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                ),
              if (c != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !widget.chrome,
                    child: AnimatedOpacity(
                      opacity: widget.chrome ? 1 : 0,
                      duration: AppMotion.short,
                      child: _Controls(
                        asset: widget.asset,
                        controller: c,
                        onScrubStart: () {
                          _wasPlaying = c.value.isPlaying;
                          c.pause();
                          setState(() => _scrubbing = true);
                        },
                        onScrubEnd: () {
                          if (_wasPlaying) c.play();
                          setState(() => _scrubbing = false);
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SeekBadge extends StatelessWidget {
  const _SeekBadge({required this.side, required this.count});
  final int side;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: side < 0 ? Alignment.centerLeft : Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: 0.4,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: side < 0
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  radius: 1,
                  colors: const <Color>[Color(0x33FFFFFF), Color(0x00FFFFFF)],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      side < 0
                          ? Icons.fast_rewind_rounded
                          : Icons.fast_forward_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    Text(
                      '${side < 0 ? '−' : '+'}${count * 10} s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Play/pause, time, loop and mute, and the filmstrip scrubber.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.asset,
    required this.controller,
    required this.onScrubStart,
    required this.onScrubEnd,
  });

  final AssetEntity asset;
  final VideoPlayerController controller;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VideoPlayerValue v = controller.value;
    final ViewerSettings s =
        ref.watch(viewerSettingsProvider).value ?? const ViewerSettings();
    const Color fg = Colors.white;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        MediaQuery.paddingOf(context).bottom + 132,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                tooltip: v.isPlaying ? 'Pause' : 'Play',
                color: fg,
                onPressed: () =>
                    v.isPlaying ? controller.pause() : controller.play(),
                icon: Icon(
                  v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              Expanded(
                child: Text(
                  '${Fmt.duration(v.position)} / ${Fmt.duration(v.duration)}',
                  style: const TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                tooltip: s.loop ? 'Loop on' : 'Loop off',
                isSelected: s.loop,
                color: fg,
                selectedIcon: const Icon(Icons.repeat_on_rounded),
                onPressed: () {
                  ref.read(viewerSettingsProvider.notifier).setLoop(!s.loop);
                  controller.setLooping(!s.loop);
                },
                icon: const Icon(Icons.repeat),
              ),
              IconButton(
                tooltip: s.muted ? 'Unmute' : 'Mute',
                color: fg,
                onPressed: () {
                  ref.read(viewerSettingsProvider.notifier).setMuted(!s.muted);
                  controller.setVolume(s.muted ? 1 : 0);
                },
                icon: Icon(
                  s.muted
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                ),
              ),
            ],
          ),
          _Filmstrip(
            asset: asset,
            controller: controller,
            onStart: onScrubStart,
            onEnd: onScrubEnd,
          ),
        ],
      ),
    );
  }
}

/// Eight frames across the video; drag anywhere on it to move the playhead.
class _Filmstrip extends StatelessWidget {
  const _Filmstrip({
    required this.asset,
    required this.controller,
    required this.onStart,
    required this.onEnd,
  });

  static const int _frames = 8;

  final AssetEntity asset;
  final VideoPlayerController controller;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final Duration total = controller.value.duration;
    final double f = total.inMilliseconds == 0
        ? 0
        : controller.value.position.inMilliseconds / total.inMilliseconds;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        void seekTo(double dx) {
          final double t = (dx / c.maxWidth).clamp(0, 1);
          controller.seekTo(total * t);
        }

        return Semantics(
          slider: true,
          label: 'Video position',
          value:
              '${Fmt.duration(controller.value.position)} of ${Fmt.duration(total)}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (DragStartDetails d) {
              onStart();
              seekTo(d.localPosition.dx);
            },
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                seekTo(d.localPosition.dx),
            onHorizontalDragEnd: (_) => onEnd(),
            onTapUp: (TapUpDetails d) => seekTo(d.localPosition.dx),
            child: SizedBox(
              height: 48,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Row(
                      children: <Widget>[
                        for (int i = 0; i < _frames; i++)
                          Expanded(
                            child: SizedBox.expand(
                              child: Image(
                                image: AssetEntityImageProvider(
                                  asset,
                                  isOriginal: false,
                                  thumbnailSize: const ThumbnailSize.square(
                                    128,
                                  ),
                                  // Glide's frame option is in microseconds.
                                  frame:
                                      (total.inMicroseconds *
                                              (i + 0.5) /
                                              _frames)
                                          .round(),
                                ),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: Color(0xFF222222)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: (c.maxWidth * f) - 2,
                    top: -3,
                    bottom: -3,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(blurRadius: 2, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
