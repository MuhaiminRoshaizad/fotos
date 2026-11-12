import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoAlertDialog, CupertinoIcons, showCupertinoDialog;
import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';
import '../theme/app_tokens.dart';

/// Runs [each] over [items] behind a dialog that shows how far it has got,
/// then how it ended, and can't be dismissed midway. Returns how many
/// failed; an item fails by throwing.
///
/// [verb] and [doneVerb] are the two tenses ("Moving", "Moved") and [what]
/// names the lot ("12 items", "report.pdf"). A single item has nothing to
/// count, so its bar runs without a fraction, unless [progress] reports how
/// far that one piece of work has got as (done, total). With [show] false
/// the work runs with no dialog at all, for something too quick to be worth
/// one.
Future<int> runBatch<T>(
  BuildContext context, {
  required String verb,
  required String doneVerb,
  required String what,
  required List<T> items,
  required Future<void> Function(T item) each,
  String Function(T item)? nameOf,
  Stream<(int, int)>? progress,
  bool show = true,
}) async {
  final ValueNotifier<_Batch> state = ValueNotifier<_Batch>(const _Batch());
  final StreamSubscription<(int, int)>? part = progress?.listen(
    ((int, int) p) => state.value = _Batch(
      done: state.value.done,
      failed: state.value.failed,
      part: p,
    ),
  );
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  if (show) {
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (BuildContext ctx) => PopScope(
          canPop: false,
          child: _BatchDialog(
            verb: verb,
            doneVerb: doneVerb,
            what: what,
            total: items.length,
            names: nameOf == null ? null : items.map(nameOf).toList(),
            state: state,
          ),
        ),
      ),
    );
  }
  int failed = 0;
  for (final T item in items) {
    try {
      await each(item);
    } on Exception {
      failed++;
    }
    state.value = _Batch(done: state.value.done + 1, failed: failed);
  }
  // Nothing more will come that matters; no need to wait for it to close.
  if (part != null) unawaited(part.cancel());
  if (show) {
    // Let the bar reach the end, then show the outcome long enough to read.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    state.value = _Batch(done: items.length, failed: failed, finished: true);
    failed == 0 ? AppHaptics.success() : AppHaptics.error();
    await Future<void>.delayed(const Duration(milliseconds: 850));
    navigator.pop();
  }
  state.dispose();
  return failed;
}

class _Batch {
  const _Batch({
    this.done = 0,
    this.failed = 0,
    this.finished = false,
    this.part,
  });
  final int done;
  final int failed;
  final bool finished;

  /// How far a single piece of work has got, when it reports that.
  final (int, int)? part;
}

class _BatchDialog extends StatelessWidget {
  const _BatchDialog({
    required this.verb,
    required this.doneVerb,
    required this.what,
    required this.total,
    required this.names,
    required this.state,
  });

  final String verb;
  final String doneVerb;
  final String what;
  final int total;
  final List<String>? names;
  final ValueNotifier<_Batch> state;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool still = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<_Batch>(
      valueListenable: state,
      builder: (BuildContext context, _Batch b, _) {
        final bool ok = b.failed == 0;
        return CupertinoAlertDialog(
          title: Text(
            !b.finished
                ? '$verb $what'
                : ok
                ? '$doneVerb $what'
                : total == 1
                ? 'Couldn\'t finish'
                : '${b.failed} of $total failed',
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            // One height for both states, so the dialog doesn't resize as
            // the bar gives way to the tick.
            child: SizedBox(
              height: 62,
              child: AnimatedSwitcher(
                duration: still ? Duration.zero : AppMotion.medium,
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (Widget child, Animation<double> a) =>
                    FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.5, end: 1).animate(a),
                        child: child,
                      ),
                    ),
                child: b.finished
                    ? Icon(
                        ok
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.exclamationmark_circle_fill,
                        key: const ValueKey<String>('outcome'),
                        size: 48,
                        color: ok ? cs.primary : cs.error,
                        semanticLabel: ok ? 'Finished' : 'Finished with errors',
                      )
                    : _Bar(
                        key: const ValueKey<String>('bar'),
                        done: b.part != null && total <= 1
                            ? b.part!.$1
                            : b.done,
                        total: b.part != null && total <= 1
                            ? b.part!.$2
                            : total,
                        name: names != null && b.done < total
                            ? names![b.done]
                            : null,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.done,
    required this.total,
    required this.name,
  });

  final int done;
  final int total;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color track = cs.onSurface.withValues(alpha: 0.12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: total <= 1
              ? LinearProgressIndicator(minHeight: 6, backgroundColor: track)
              // The bar glides to each new count instead of jumping.
              : TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: done / total),
                  duration: AppMotion.medium,
                  curve: Curves.easeOut,
                  builder: (_, double v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor: track,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (total > 1)
          Text(
            done >= total ? 'Finishing…' : '${done + 1} of $total',
            style: const TextStyle(
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        if (name != null)
          Text(
            name!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
      ],
    );
  }
}
