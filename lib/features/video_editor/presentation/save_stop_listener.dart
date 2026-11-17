import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart' show rootNavigatorKey;
import '../../../core/platform/native_channel.dart';
import '../../albums/presentation/albums_providers.dart'
    show nativeChannelProvider;
import 'save_job.dart';
import 'save_progress.dart';

/// Hears the save notification's Stop... and asks in fotos whether to stop
/// the save: an open saving dialog turns to the question, or one opens on
/// it. If the save has ended by the time fotos is up, nothing is asked.
///
/// Android brings fotos up for it whatever state it was in: on screen, in
/// the background (onNewIntent, as the askStopSave event), or not running at
/// all (launchAsksStop, read once at startup, after the save in progress
/// has been picked up from Android).
class SaveStopListener extends ConsumerStatefulWidget {
  const SaveStopListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SaveStopListener> createState() => _SaveStopListenerState();
}

class _SaveStopListenerState extends ConsumerState<SaveStopListener> {
  StreamSubscription<Object?>? _sub;

  /// A request is being answered: a second tap meanwhile must not open a
  /// second dialog.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final NativeChannel native = ref.read(nativeChannelProvider);
    _sub = native.events('askStopSave').listen((_) => _ask());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (await native.invoke<bool>('launchAsksStop') ?? false) {
          await _ask();
        }
      } on PlatformException {
        // Opened some other way.
      } on MissingPluginException {
        // Widget tests run without the Android side.
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_busy) return;
    _busy = true;
    try {
      // Opened from cold, fotos first learns what Android is saving.
      await ref.read(saveJobProvider.notifier).ready;
      final NavigatorState? root = await _root();
      if (!mounted || root == null) return;
      // Ended while fotos came up: there is nothing left to stop.
      if (ref.read(saveJobProvider) == null) return;
      if (SavingDialog.isOpen) {
        ref.read(saveStopAskProvider.notifier).ask();
        return;
      }
      unawaited(root.push(saveDialogRoute(root.context, ask: true)));
      // Held until the dialog has been built and counts as open.
      await SchedulerBinding.instance.endOfFrame;
    } finally {
      _busy = false;
    }
  }

  /// The app's navigator, waiting out the first frames of a cold start
  /// (up to five seconds) until it exists.
  Future<NavigatorState?> _root() async {
    for (int i = 0; i < 100; i++) {
      final NavigatorState? root = rootNavigatorKey.currentState;
      if (root != null) return root;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
