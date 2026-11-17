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

/// What became of a save started from the editor: the [saved] video, or
/// [hidden] to finish in the background; neither when it was cancelled or
/// failed.
typedef EditorSave = ({SavedEdit? saved, bool hidden});

/// Saves [plan] of video [id] (file [name]) behind a dialog that shows how
/// far the encode has got. It can be cancelled until saving begins, or
/// hidden to finish in the background. A failure is explained here. The
/// original is untouched unless this returns an edit that replaced it.
Future<EditorSave> saveWithProgress(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String name,
  required CutPlan plan,
  required bool replace,
}) async {
  const EditorSave none = (saved: null, hidden: false);
  final SaveJobNotifier job = ref.read(saveJobProvider.notifier);
  late final Future<SavedEdit?> saving;
  try {
    saving = await job.start(id, name, plan, replace: replace);
  } on CutException catch (e) {
    if (context.mounted) await _sayWhy(context, e);
    return none;
  }
  if (!context.mounted) return none;
  // Closes itself when the save ends or is hidden.
  final Future<void> closed = showSaveDialog(context);
  try {
    final SavedEdit? saved = await saving;
    await closed;
    if (saved == null) return (saved: null, hidden: true);
    unawaited(AppHaptics.success());
    return (saved: saved, hidden: false);
  } on CutException catch (e) {
    await closed;
    if (e.reason == CutFailure.cancelled) return none;
    if (context.mounted) await _sayWhy(context, e);
    return none;
  }
}

/// Shows how the save under way is going, over everything: from the editor,
/// and again from the progress pill. It closes itself when the save ends or
/// is hidden.
Future<void> showSaveDialog(BuildContext context) => showCupertinoDialog<void>(
  context: context,
  useRootNavigator: true,
  builder: (BuildContext ctx) =>
      const PopScope(canPop: false, child: SavingDialog()),
);

Future<void> _sayWhy(BuildContext context, CutException failure) async {
  unawaited(AppHaptics.error());
  await showCupertinoDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (BuildContext ctx) => CupertinoAlertDialog(
      title: const Text('Couldn\'t save the edit'),
      content: Text(switch (failure.reason) {
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
}

/// How far the save under way has got, with the time left, Cancel and Hide.
/// Cancel asks first, in the same dialog: stopping loses the encode so far,
/// and for a hidden save the cuts too, since the editor has closed.
class SavingDialog extends ConsumerStatefulWidget {
  const SavingDialog({super.key});

  @override
  ConsumerState<SavingDialog> createState() => _SavingDialogState();
}

class _SavingDialogState extends ConsumerState<SavingDialog> {
  late final Timer _tick;
  bool _closed = false;

  /// Cancel was tapped: the dialog is asking whether to stop.
  bool _asking = false;

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

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final SaveJobNotifier job = ref.read(saveJobProvider.notifier);
    final SaveJob? now = ref.watch(saveJobProvider);
    ref.listen<SaveJob?>(saveJobProvider, (SaveJob? _, SaveJob? next) {
      if (next == null) _close();
    });
    // Ended before this first showed: nothing left to show.
    if (now == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
    final int p = now?.percent ?? 100;
    // At 100 the encode is done and the file is being checked and named:
    // too late to stop safely.
    final bool finishing = p >= 100;
    const TextStyle figures = TextStyle(
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );
    final Color secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    // Too late to stop once finishing: back to the progress, which then
    // offers no Cancel.
    final bool asking = _asking && !finishing && now != null;
    // The question fades in over the progress and back, in place.
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.short,
      child: KeyedSubtree(
        key: ValueKey<bool>(asking),
        child: asking
            ? _confirm(job, now)
            : _progress(job, p, finishing, figures, secondary),
      ),
    );
  }

  /// Whether to stop, and what stopping loses.
  Widget _confirm(SaveJobNotifier job, SaveJob now) => CupertinoAlertDialog(
    title: const Text('Stop saving?'),
    content: Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        now.hidden
            ? 'The edit will be lost. ${now.name} stays as it is.'
            : 'Your cuts stay in the editor, so you can save again. '
                  '${now.name} stays as it is.',
      ),
    ),
    actions: <Widget>[
      // iOS bolds the safe choice when the other destroys.
      CupertinoDialogAction(
        isDefaultAction: true,
        onPressed: () => setState(() => _asking = false),
        child: const Text('Keep Saving'),
      ),
      CupertinoDialogAction(
        isDestructiveAction: true,
        onPressed: job.cancel,
        child: const Text('Stop Saving'),
      ),
    ],
  );

  /// How far the save has got, with Cancel and Hide.
  Widget _progress(
    SaveJobNotifier job,
    int p,
    bool finishing,
    TextStyle figures,
    Color secondary,
  ) => CupertinoAlertDialog(
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
            style: figures.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Hide this to keep using your phone. The save carries on.',
            style: TextStyle(color: secondary),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      CupertinoDialogAction(
        isDestructiveAction: true,
        onPressed: finishing ? null : () => setState(() => _asking = true),
        child: const Text('Cancel'),
      ),
      CupertinoDialogAction(
        isDefaultAction: true,
        onPressed: () {
          job.hide();
          _close();
        },
        child: const Text('Hide'),
      ),
    ],
  );
}
