import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/viewer_settings.dart';
import 'video_session.dart';
import 'viewer_glass.dart';

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
  late final VideoSession _session = VideoSession(_newController)
    ..addListener(_tick);
  File? _file;
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
    try {
      await _session.start();
    } on Exception {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted && widget.active) _session.play();
  }

  /// An initialised player for this video with the saved loop and mute
  /// settings, for the session to open now and again after the end.
  Future<VideoPlayerController> _newController() async {
    final File? f = _file ??= await widget.asset.file;
    if (f == null) throw const FileSystemException('The video has no file');
    final VideoPlayerController c = VideoPlayerController.file(f);
    try {
      await c.initialize();
      final ViewerSettings s =
          ref.read(viewerSettingsProvider).value ?? const ViewerSettings();
      await c.setLooping(s.loop);
      await c.setVolume(s.muted ? 0 : 1);
    } on Exception {
      await c.dispose();
      rethrow;
    }
    return c;
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(VideoPage old) {
    super.didUpdateWidget(old);
    if (old.active == widget.active) return;
    widget.active ? _session.play() : _session.pause();
  }

  @override
  void dispose() {
    _seekBadge?.cancel();
    _session
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  int _side(double x, double width) {
    if (x < width * 0.38) return -1;
    if (x > width * 0.62) return 1;
    return 0;
  }

  void _seek(int side) {
    if (_session.controller == null) return;
    final DateTime now = DateTime.now();
    if (side != _streakSide || now.difference(_streakAt).inMilliseconds > 700) {
      _streakCount = 0;
    }
    _streakSide = side;
    _streakCount++;
    _streakAt = now;
    // Count from the last target, so quick taps add up instead of all
    // starting from the position the player has yet to leave.
    _session.seekTo(_session.position + Duration(seconds: 10 * side));
    AppHaptics.light();
    _seekBadge?.cancel();
    _seekBadge = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _streakSide = 0);
    });
    setState(() {});
  }

  void _togglePlay() {
    final VideoPlayerController? c = _session.controller;
    if (c == null) return;
    c.value.isPlaying ? _session.pause() : _session.play();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _session.controller;
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

    // The slide-out page doesn't put the video under the viewer's Material,
    // so give it its own; without one, text falls back to Flutter's
    // unstyled debug look.
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 14),
        child: _page(c, picture),
      ),
    );
  }

  Widget _page(VideoPlayerController? c, Widget picture) {
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
            _session.setSpeed(2);
            _session.play();
            AppHaptics.light();
            setState(() => _fast = true);
          },
          onLongPressEnd: (_) {
            if (c == null) return;
            _session.setSpeed(1);
            if (!_wasPlaying) _session.pause();
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
                      icon: CupertinoIcons.forward_fill,
                    ),
                  ),
                ),
              if (c != null &&
                  !c.value.isPlaying &&
                  !_scrubbing &&
                  widget.chrome)
                Center(
                  child: ViewerGlass(
                    shape: const CircleBorder(),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(72, 72),
                      onPressed: _togglePlay,
                      child: const Icon(
                        CupertinoIcons.play_fill,
                        size: 32,
                        color: Colors.white,
                        semanticLabel: 'Play',
                      ),
                    ),
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
                        position: _session.position,
                        gliding: c.value.isPlaying && _session.target == null,
                        onPlayPause: _togglePlay,
                        onSeek: _session.seekTo,
                        onScrubStart: () {
                          _wasPlaying = c.value.isPlaying;
                          _session.pause();
                          setState(() => _scrubbing = true);
                        },
                        onScrubEnd: () {
                          setState(() => _scrubbing = false);
                          if (!_wasPlaying) return;
                          // Start again only once the last seek has landed,
                          // so playback picks up from the chosen frame.
                          _session.settled.then((_) {
                            if (mounted && !_scrubbing) _session.play();
                          });
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
                          ? CupertinoIcons.backward_fill
                          : CupertinoIcons.forward_fill,
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
  Widget build(BuildContext context) => ViewerGlass(
    shape: const StadiumBorder(),
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
    required this.position,
    required this.gliding,
    required this.onPlayPause,
    required this.onSeek,
    required this.onScrubStart,
    required this.onScrubEnd,
  });

  final AssetEntity asset;
  final VideoPlayerController controller;

  /// The position to show: the seek target while one is under way.
  final Duration position;

  /// Whether the playhead should glide between the player's position
  /// reports, which arrive ten times a second.
  final bool gliding;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VideoPlayerValue v = controller.value;
    final ViewerSettings s =
        ref.watch(viewerSettingsProvider).value ?? const ViewerSettings();
    const Color fg = Colors.white;
    Widget button(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool dim = false,
    }) => Tooltip(
      message: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 44),
        onPressed: onTap,
        child: Icon(
          icon,
          size: AppIconSize.dense + 2,
          color: dim ? Colors.white54 : fg,
          semanticLabel: label,
        ),
      ),
    );
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
          ViewerGlass(
            shape: const StadiumBorder(),
            child: Row(
              children: <Widget>[
                button(
                  v.isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  v.isPlaying ? 'Pause' : 'Play',
                  onPlayPause,
                ),
                Expanded(
                  child: Text(
                    '${Fmt.duration(position)} / ${Fmt.duration(v.duration)}',
                    maxLines: 1,
                    style: const TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                button(
                  s.loop ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat,
                  s.loop ? 'Loop on' : 'Loop off',
                  () {
                    ref.read(viewerSettingsProvider.notifier).setLoop(!s.loop);
                    controller.setLooping(!s.loop);
                  },
                  dim: !s.loop,
                ),
                button(
                  s.muted
                      ? CupertinoIcons.speaker_slash
                      : CupertinoIcons.speaker_2,
                  s.muted ? 'Unmute' : 'Mute',
                  () {
                    ref
                        .read(viewerSettingsProvider.notifier)
                        .setMuted(!s.muted);
                    controller.setVolume(s.muted ? 1 : 0);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Filmstrip(
            asset: asset,
            controller: controller,
            position: position,
            gliding: gliding,
            onSeek: onSeek,
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
    required this.position,
    required this.gliding,
    required this.onSeek,
    required this.onStart,
    required this.onEnd,
  });

  static const int _frames = 8;

  final AssetEntity asset;
  final VideoPlayerController controller;
  final Duration position;
  final bool gliding;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final Duration total = controller.value.duration;
    final double f = total.inMilliseconds == 0
        ? 0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        void seekTo(double dx) {
          final double t = (dx / c.maxWidth).clamp(0, 1);
          onSeek(total * t);
        }

        return Semantics(
          slider: true,
          label: 'Video position',
          value: '${Fmt.duration(position)} of ${Fmt.duration(total)}',
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
                                // Some videos can't give a frame at every
                                // time; show the cover frame there instead.
                                errorBuilder: (_, _, _) => Image(
                                  image: AssetEntityImageProvider(
                                    asset,
                                    isOriginal: false,
                                    thumbnailSize: const ThumbnailSize.square(
                                      128,
                                    ),
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  AnimatedPositioned(
                    // The player reports its position every 100 ms; glide
                    // across that gap while playing, and jump when seeking.
                    duration: gliding
                        ? const Duration(milliseconds: 100)
                        : Duration.zero,
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
