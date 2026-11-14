import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' show LinearProgressIndicator, Theme;

import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/video_cutter.dart';
import '../domain/cut_plan.dart';
import '../domain/save_estimate.dart';

/// Saves [plan] behind a dialog that shows how far the encode has got and
/// can be cancelled until saving begins. Returns the saved video, or null
/// when cancelled or failed (after saying why). The original is untouched
/// unless this returns an edit that replaced it.
Future<SavedEdit?> saveWithProgress(
  BuildContext context,
  VideoCutter cutter, {
  required String id,
  required CutPlan plan,
  required bool replace,
}) async {
  final ValueNotifier<int> percent = ValueNotifier<int>(0);
  final StreamSubscription<int> sub = cutter
      .progressOf(plan)
      .listen((int p) => percent.value = p);
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showCupertinoDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext ctx) => PopScope(
        canPop: false,
        child: _SavingDialog(percent: percent, onCancel: cutter.cancel),
      ),
    ),
  );
  SavedEdit? saved;
  CutException? failure;
  try {
    saved = await cutter.save(id, plan, replace: replace);
  } on CutException catch (e) {
    failure = e;
  }
  await sub.cancel();
  navigator.pop();
  percent.dispose();
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
        CutFailure.afterTrash =>
          'The original went to Recently deleted, but the edit couldn\'t '
              'be finished. Restore the original from Recently deleted.',
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

class _SavingDialog extends StatefulWidget {
  const _SavingDialog({required this.percent, required this.onCancel});

  final ValueListenable<int> percent;
  final VoidCallback onCancel;

  @override
  State<_SavingDialog> createState() => _SavingDialogState();
}

class _SavingDialogState extends State<_SavingDialog> {
  final Stopwatch _clock = Stopwatch()..start();
  late final SaveEstimate _estimate = SaveEstimate(() => _clock.elapsed);

  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    widget.percent.addListener(_report);
    // The time left counts down between progress reports.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  void _report() {
    _estimate.report(widget.percent.value);
    setState(() {});
  }

  @override
  void dispose() {
    _tick.cancel();
    widget.percent.removeListener(_report);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int p = widget.percent.value;
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
              finishing ? ' ' : timeLeft(_estimate.left),
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
          onPressed: finishing ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
