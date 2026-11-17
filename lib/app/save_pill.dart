import 'dart:async';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/media/media_flight.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/motion.dart';
import '../features/video_editor/domain/save_estimate.dart';
import '../features/video_editor/presentation/save_job.dart';
import '../features/video_editor/presentation/save_progress.dart';
import '../features/video_editor/presentation/save_ring.dart';
import 'floating_nav.dart';

/// A save hidden to run in the background, at the foot of the page (above
/// the tab bar on the four tab pages): a ring that fills as it goes, the
/// video's name and the time left. A tap brings back its dialog, with
/// Cancel. A viewer opened over it shows the ring alone at its top right
/// ([SaveRing]), and the pill turns into it on the way ([_flight]).
class SavePill extends ConsumerStatefulWidget {
  const SavePill({super.key});

  /// Room between the glass's edge and the ring, and after the words.
  static const EdgeInsets inset = EdgeInsets.fromLTRB(
    AppSpacing.sm,
    AppSpacing.sm,
    AppSpacing.lg,
    AppSpacing.sm,
  );

  static const double ringSize = 28;

  @override
  ConsumerState<SavePill> createState() => _SavePillState();
}

class _SavePillState extends ConsumerState<SavePill> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // The time left counts down between progress reports.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SaveJob? job = ref.watch(saveJobProvider);
    if (job == null) return const SizedBox.shrink();
    final String detail = job.percent >= 100
        ? 'Finishing'
        : '${job.percent}% · '
              '${timeLeft(ref.read(saveJobProvider.notifier).left)}';
    return Pressable(
      label: 'Saving ${job.name}. Show progress',
      onTap: () => showSaveDialog(context),
      child: Hero(
        tag: saveHeroTag,
        createRectTween: mediaFlightTween,
        flightShuttleBuilder: _flight(job, detail),
        child: FrostedPill(
          child: Padding(
            padding: SavePill.inset,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SaveRingIndicator(
                  percent: job.percent,
                  size: SavePill.ringSize,
                ),
                const SizedBox(width: AppSpacing.md),
                _Words(name: job.name, detail: detail),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pill's two lines: what is saving, and how far along.
class _Words extends StatelessWidget {
  const _Words({required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Saving $name',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          Text(
            detail,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// What flies between the pill and the viewer's ring, both ways.
///
/// It is drawn to match each end exactly, so nothing jumps as the flight
/// takes over or hands back: the pill's tint, edge, shadow, blur, ring and
/// words at one end; the ring button's tint, edge and smaller ring at the
/// other. In between everything follows the flight's own eased progress,
/// the same value that moves its box: the box narrows to a circle, the
/// ring slides from the pill's left end to the middle and shrinks from 28
/// to 24 at the same line width, the words fade over the first third, and
/// the blur and shadow fade out as the box reaches the viewer's ring.
HeroFlightShuttleBuilder _flight(SaveJob job, String detail) =>
    (
      BuildContext flightContext,
      Animation<double> animation,
      HeroFlightDirection direction,
      BuildContext fromHeroContext,
      BuildContext toHeroContext,
    ) {
      // The pill's look, read where the pill lives (it follows the app's
      // theme; the viewer is always dark).
      final BuildContext pill = direction == HeroFlightDirection.push
          ? fromHeroContext
          : toHeroContext;
      final Color pillFill = FrostedPill.fill(pill);
      final BorderSide pillEdge = FrostedPill.edge(pill);
      final BoxShadow pillShadow = FrostedPill.shadow(pill);
      final Color pillTrack = Theme.of(
        pill,
      ).colorScheme.surfaceContainerHighest;
      final ThemeData theme = Theme.of(pill);
      // Where the ring sits inside the pill, from the glass's left edge.
      final double pillRingLeft =
          FrostedPill.padding.left + SavePill.inset.left;
      final double wordsLeft = pillRingLeft + SavePill.ringSize + AppSpacing.md;
      return Theme(
        data: theme,
        child: AnimatedBuilder(
          animation: animation,
          builder: (BuildContext context, _) {
            // 0 is the pill and 1 the ring, whichever way it flies.
            final double t = animation.value;
            final Color fill = Color.lerp(pillFill, SaveRing.fill, t)!;
            final BorderSide edge = BorderSide.lerp(pillEdge, SaveRing.edge, t);
            final BoxShadow shadow = pillShadow
                .scale(1)
                .copyWith(
                  color: pillShadow.color.withValues(
                    alpha: pillShadow.color.a * (1 - t),
                  ),
                );
            final double sigma = FrostedPill.sigma * (1 - t);
            final double ring = lerpDouble(
              SavePill.ringSize,
              SaveRing.ringSize,
              t,
            )!;
            final double words = (1 - t * 3).clamp(0.0, 1.0);
            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final double w = c.maxWidth, h = c.maxHeight;
                final double ringLeft = lerpDouble(
                  pillRingLeft,
                  (w - ring) / 2,
                  t,
                )!;
                final ShapeBorder shape = StadiumBorder(side: edge);
                return DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    shadows: <BoxShadow>[shadow],
                  ),
                  child: ClipPath(
                    clipper: const ShapeBorderClipper(shape: StadiumBorder()),
                    child: BackdropFilter(
                      enabled: sigma > 0.5,
                      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                      child: DecoratedBox(
                        decoration: ShapeDecoration(color: fill, shape: shape),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            if (words > 0)
                              Positioned(
                                left: wordsLeft,
                                top: 0,
                                bottom: 0,
                                child: Opacity(
                                  opacity: words,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: 1,
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: _Words(
                                        name: job.name,
                                        detail: detail,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              left: ringLeft,
                              top: (h - ring) / 2,
                              child: SaveRingIndicator(
                                percent: job.percent,
                                size: ring,
                                track: Color.lerp(pillTrack, SaveRing.track, t),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    };
