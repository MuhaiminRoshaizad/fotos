import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator, Theme;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/video_cutter.dart';
import '../domain/cut_plan.dart';
import '../domain/save_estimate.dart';
import 'save_job.dart';

/// Saves [plan] of video [id] (file [name]) behind a dialog that shows how
/// far the encode has got and can be cancelled until saving begins. Returns
/// the saved video, or null when cancelled or failed (after saying why).
/// The original is untouched unless this returns an edit that replaced it.
Future<SavedEdit?> saveWithProgress(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String name,
  required CutPlan plan,
  required bool replace,
}) async {
  final SaveJobNotifier job = ref.read(saveJobProvider.notifier);
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  SavedEdit? saved;
  CutException? failure;
  try {
    final Future<SavedEdit> saving = job.save(id, name, plan, replace: replace);
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (BuildContext ctx) =>
            const PopScope(canPop: false, child: SavingDialog()),
      ),
    );
    try {
      saved = await saving;
    } finally {
      navigator.pop();
    }
  } on CutException catch (e) {
    failure = e;
  }
  if (saved != null) {
    unawaited(AppHaptics.success());
    return saved;
  }
  if (failure == null || failure.reason == CutFailure.cancelled) return null;
  unawaited(AppHaptics.error());
  if (!context.mounted) return null;
  await showCupertinoDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (BuildContext ctx) => CupertinoAlertDialog(
      title: const Text('Couldn\'t save the edit'),
      content: Text(switch (failure!.reason) {
        CutFailure.noSpace =>
          'There isn\'t enough free space. The original video is unchanged.',
        CutFailure.noAccess =>
          'fotos needs All files access to save beside the original. The '
              'original video is unchanged.',
        CutFailure.busy => 'Another video is still saving.',
        _ =>
          'Something went wrong while saving. The original video is '
              'unchanged.',
      }),
      actions: <Widget>[
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return null;
}

/// How far the save under way has got, with the time left, and Cancel.
class SavingDialog extends ConsumerStatefulWidget {
  const SavingDialog({super.key});

  @override
  ConsumerState<SavingDialog> createState() => _SavingDialogState();
}

class _SavingDialogState extends ConsumerState<SavingDialog> {
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
    final SaveJobNotifier job = ref.read(saveJobProvider.notifier);
    // Before Android has started the save there is no job yet.
    final int p = ref.watch(saveJobProvider)?.percent ?? 0;
    // At 100 the encode is done and the file is being checked and named:
    // too late to stop safely.
    final bool finishing = p >= 100;
    const TextStyle figures = TextStyle(
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );
    return CupertinoAlertDialog(
      title: Text(finishing ? 'Finishing' : 'Saving video'),
      content: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                value: finishing ? null : p / 100,
                minHeight: 6,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(finishing ? 'Checking the new video' : '$p%', style: figures),
            // Always one line here, so the dialog doesn't change size.
            Text(
              finishing ? ' ' : timeLeft(job.left),
              style: figures.copyWith(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: finishing ? null : job.cancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
