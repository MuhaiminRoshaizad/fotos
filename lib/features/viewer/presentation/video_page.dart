import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/zoom_view.dart';
import '../data/viewer_settings.dart';
import '../../../core/video/strip_tiles.dart';
import '../../../core/video/video_frames.dart';
import '../../../core/video/video_session.dart';
import 'viewer_glass.dart';
import 'viewer_metrics.dart';

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
    this.onZoomed,
  });

  final AssetEntity asset;

  /// Called when the video is pinched in, or back to normal size, so the
  /// viewer can stop paging while it is zoomed.
  final ValueChanged<bool>? onZoomed;

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
  bool _opened = false;
  Animation<double>? _routeIn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened || _routeIn != null) return;
    // While the viewer's route flies in, the Hero around this page drops
    // the page and builds it again on landing. A player opened before then
    // belongs to a page about to be thrown away, and opening one twice
    // doubled the wait for the first frame.
    final Animation<double>? route = ModalRoute.of(context)?.animation;
    if (route == null || route.isCompleted) {
      _opened = true;
      _open();
    } else {
      _routeIn = route..addStatusListener(_onRouteIn);
    }
  }

  void _onRouteIn(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeIn?.removeStatusListener(_onRouteIn);
    _routeIn = null;
    _opened = true;
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
      // The page may be gone by now, and ref with it. The session disposes
      // a player handed to it after its own disposal, so only the settings
      // are skipped; anything thrown here must not strand the player.
      if (mounted) {
        final ViewerSettings s =
            ref.read(viewerSettingsProvider).value ?? const ViewerSettings();
        await c.setLooping(s.loop);
        await c.setVolume(s.muted ? 0 : 1);
      }
    } on Object {
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
    _routeIn?.removeStatusListener(_onRouteIn);
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
        // The buttons sit beside the gesture layer, not inside it. Inside,
        // every tap on Play, Loop or Mute waited out the double-tap window
        // (about 300 ms) before it was allowed to count.
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
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
                    // Pinch zooms a playing video; a double-tap here keeps
                    // skipping and playing, so it doesn't zoom.
                    if (c == null)
                      Center(child: picture)
                    else
                      ZoomView(
                        doubleTap: false,
                        onZoomed: widget.onZoomed,
                        child: Center(child: picture),
                      ),
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
                  ],
                ),
              ),
            ),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                reverseDuration: const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (Widget child, Animation<double> a) =>
                    FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.7, end: 1).animate(a),
                        child: child,
                      ),
                    ),
                child:
                    c != null &&
                        !c.value.isPlaying &&
                        !_scrubbing &&
                        widget.chrome
                    ? ViewerGlass(
                        key: const ValueKey<String>('play'),
                        shape: const CircleBorder(),
                        child: Pressable(
                          label: 'Play',
                          minSize: const Size(72, 72),
                          onTap: _togglePlay,
                          child: const Icon(
                            CupertinoIcons.play_fill,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
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
                      path: _file!.path,
                      modified: widget.asset.modifiedDateSecond ?? 0,
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
    required this.path,
    required this.modified,
    required this.controller,
    required this.position,
    required this.gliding,
    required this.onPlayPause,
    required this.onSeek,
    required this.onScrubStart,
    required this.onScrubEnd,
  });

  final String path;
  final int modified;
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
    const double glyph = AppIconSize.dense + 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        // Just above the viewer's thumbnail strip and action bar, as one
        // group with them.
        MediaQuery.paddingOf(context).bottom +
            ViewerMetrics.bottomBars +
            AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ViewerGlass(
            shape: const StadiumBorder(),
            child: Row(
              children: <Widget>[
                Pressable(
                  label: v.isPlaying ? 'Pause' : 'Play',
                  onTap: onPlayPause,
                  child: GlyphSwap(
                    icon: v.isPlaying
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: glyph,
                    color: fg,
                  ),
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
                // One glyph for both states: dim while off, bright while
                // on, and it turns once as it comes on.
                Pressable(
                  label: s.loop ? 'Loop on' : 'Loop off',
                  onTap: () {
                    if (!s.loop) AppHaptics.light();
                    ref.read(viewerSettingsProvider.notifier).setLoop(!s.loop);
                    controller.setLooping(!s.loop);
                  },
                  child: TurnOnGlyph(
                    icon: CupertinoIcons.repeat,
                    on: s.loop,
                    size: glyph,
                  ),
                ),
                Pressable(
                  label: s.muted ? 'Unmute' : 'Mute',
                  onTap: () {
                    ref
                        .read(viewerSettingsProvider.notifier)
                        .setMuted(!s.muted);
                    controller.setVolume(s.muted ? 1 : 0);
                  },
                  child: GlyphSwap(
                    icon: s.muted
                        ? CupertinoIcons.speaker_slash
                        : CupertinoIcons.speaker_2,
                    size: glyph,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Filmstrip(
            path: path,
            modified: modified,
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
/// Each slot shows a picture from its own eighth, from its start where it
/// can, so the first slot is the opening frame; each fades in as soon as it
/// is read, those nearest the playhead first.
class _Filmstrip extends ConsumerWidget {
  const _Filmstrip({
    required this.path,
    required this.modified,
    required this.controller,
    required this.position,
    required this.gliding,
    required this.onSeek,
    required this.onStart,
    required this.onEnd,
  });

  static const int _slots = 8;

  final String path;

  /// When the file last changed, in seconds: a new version gets new frames.
  final int modified;
  final VideoPlayerController controller;
  final Duration position;
  final bool gliding;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VideoFrames frames = ref.watch(
      videoFramesProvider((path: path, modified: modified)),
    );
    final Duration total = controller.value.duration;
    final int length = total.inMilliseconds;
    final List<Stretch> slots = <Stretch>[
      for (int i = 0; i < _slots; i++)
        (from: length * i ~/ _slots, until: length * (i + 1) ~/ _slots),
    ];
    if (length > 0) {
      frames.want(slots, focus: position.inMilliseconds);
    }
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
                    child: ListenableBuilder(
                      listenable: frames,
                      builder: (BuildContext context, _) => Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          StripLoading(
                            loading:
                                length <= 0 ||
                                slots.any(
                                  (Stretch s) =>
                                      frames.loading(s.from, s.until),
                                ),
                          ),
                          Row(
                            children: <Widget>[
                              for (final Stretch s in slots)
                                Expanded(
                                  child: FrameTile(
                                    frame: frames.frameIn(s.from, s.until),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
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
