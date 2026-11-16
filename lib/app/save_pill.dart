import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../core/widgets/motion.dart';
import '../features/video_editor/domain/save_estimate.dart';
import '../features/video_editor/presentation/save_job.dart';
import '../features/video_editor/presentation/save_progress.dart';
import 'floating_nav.dart';

/// A save hidden to run in the background, above the tab bar: a ring that
/// fills as it goes, the video's name and the time left. A tap brings back
/// its dialog, with Cancel.
class SavePill extends ConsumerStatefulWidget {
  const SavePill({super.key});

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
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool finishing = job.percent >= 100;
    final String detail = finishing
        ? 'Finishing'
        : '${job.percent}% · '
              '${timeLeft(ref.read(saveJobProvider.notifier).left)}';
    return Pressable(
      label: 'Saving ${job.name}. Show progress',
      onTap: () => showSaveDialog(context),
      child: FrostedPill(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: 28,
                // The ring eases to each new percent rather than ticking.
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: job.percent / 100),
                  duration: AppMotion.long,
                  curve: AppMotion.decelerate,
                  builder: (_, double v, _) => CircularProgressIndicator(
                    value: finishing ? null : v,
                    strokeWidth: 3,
                    strokeCap: StrokeCap.round,
                    color: cs.primary,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Saving ${job.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
