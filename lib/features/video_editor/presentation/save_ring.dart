import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/media_flight.dart';
import '../../../core/theme/app_tokens.dart';
import 'save_job.dart';
import 'save_progress.dart';

/// Ties the save pill under a page to the ring in a viewer opened over it,
/// so one turns into the other as the viewer opens and closes.
const String saveHeroTag = 'background-save';

/// A hidden save's progress as a ring: filling to [percent], spinning once
/// it reaches 100 and Android is finishing the file.
class SaveRingIndicator extends StatelessWidget {
  const SaveRingIndicator({
    super.key,
    required this.percent,
    this.size = 28,
    this.track,
  });

  final int percent;
  final double size;

  /// The unfilled part; the theme's raised surface when null.
  final Color? track;

  /// The ring's line, the same at every size so nothing thickens or thins
  /// as the pill turns into the viewer's ring.
  static const double stroke = 3;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool finishing = percent >= 100;
    return SizedBox.square(
      dimension: size,
      // The ring eases to each new percent rather than ticking.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: percent / 100),
        duration: AppMotion.long,
        curve: AppMotion.decelerate,
        builder: (_, double v, _) => CircularProgressIndicator(
          value: finishing ? null : v,
          strokeWidth: stroke,
          strokeCap: StrokeCap.round,
          color: cs.primary,
          backgroundColor: track ?? cs.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// The save in a viewer's top bar: a ring at the top right while a hidden
/// save runs, nothing otherwise. A tap brings back the save's dialog. The
/// pill under the viewer turns into it as the viewer opens, and back as it
/// closes; the pill's side draws that flight.
///
/// A plain translucent circle, not the viewer's frosted glass: over a
/// playing video each blur is redrawn every frame, and the circle is small
/// enough that a blur would not show.
class SaveRing extends ConsumerWidget {
  const SaveRing({super.key, required this.flies});

  /// False while the viewer's bar is hidden, so closing the viewer does not
  /// fly an invisible ring down into the pill.
  final bool flies;

  /// The circle's size, matching the bar's other buttons.
  static const double size = 44;

  /// The ring inside it.
  static const double ringSize = 24;

  /// The circle's tint and hairline edge, and the ring's unfilled part.
  static const Color fill = Color(0xB31C1C1E);
  static const BorderSide edge = BorderSide(
    color: Color(0x1FFFFFFF),
    width: 0.5,
  );
  static const Color track = Color(0x2EFFFFFF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SaveJob? job = ref.watch(saveJobProvider);
    if (job == null || !job.hidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: Semantics(
        button: true,
        label: 'Saving ${job.name}, ${job.percent}%. Show progress',
        child: HeroMode(
          enabled: flies,
          child: Hero(
            tag: saveHeroTag,
            createRectTween: mediaFlightTween,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(size, size),
              onPressed: () => showSaveDialog(context),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: const ShapeDecoration(
                  color: fill,
                  shape: CircleBorder(side: edge),
                ),
                child: ExcludeSemantics(
                  child: SaveRingIndicator(
                    percent: job.percent,
                    size: ringSize,
                    track: track,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
