import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart' show rootNavigatorKey;
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/widgets/toast.dart';
import '../../viewer/presentation/view_intent_handler.dart';
import '../data/video_cutter.dart';
import 'save_job.dart';

/// What fotos says when a hidden save ends: [failed] for the red toast.
({String message, bool failed}) toldEnd(HiddenEnd e) {
  final SavedEdit? saved = e.end.saved;
  if (saved != null) {
    return (
      message: saved.replaced
          ? 'Replaced ${e.name} with the edit'
          : 'Saved ${saved.name}',
      failed: false,
    );
  }
  return switch (e.end.error!.reason) {
    CutFailure.cancelled => (
      message: 'Save cancelled. ${e.name} is unchanged.',
      failed: false,
    ),
    CutFailure.noSpace => (
      message:
          'Couldn\'t save the edit: not enough free space. '
          '${e.name} is unchanged.',
      failed: true,
    ),
    _ => (
      message: 'Couldn\'t save the edit. ${e.name} is unchanged.',
      failed: true,
    ),
  };
}

/// Tells how a save left to run in the background ended, on whatever is
/// showing, with Open for the new video. (Outside fotos, Android's
/// notification tells it instead.)
class SaveEndListener extends ConsumerStatefulWidget {
  const SaveEndListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SaveEndListener> createState() => _SaveEndListenerState();
}

class _SaveEndListenerState extends ConsumerState<SaveEndListener> {
  StreamSubscription<HiddenEnd>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(saveJobProvider.notifier).hiddenEnds.listen(_tell);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _tell(HiddenEnd e) {
    final SavedEdit? saved = e.end.saved;
    if (saved != null) {
      ref
        ..invalidate(libraryProvider)
        ..invalidate(albumsProvider)
        ..invalidate(favouritesProvider);
      unawaited(AppHaptics.success());
    } else if (e.end.error!.reason != CutFailure.cancelled) {
      unawaited(AppHaptics.error());
    }
    // The root navigator's own context sits above its overlay, so the
    // overlay is handed over directly.
    final NavigatorState? root = rootNavigatorKey.currentState;
    if (root == null || !root.mounted) return;
    final ({String message, bool failed}) told = toldEnd(e);
    // Android can be slow to list a new file; then there is nothing to open.
    final bool open = saved != null && saved.id.isNotEmpty;
    showToast(
      root.context,
      told.message,
      overlay: root.overlay,
      failed: told.failed,
      actionLabel: open ? 'Open' : null,
      onAction: open ? () => openInViewer(ref, saved.id) : null,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
