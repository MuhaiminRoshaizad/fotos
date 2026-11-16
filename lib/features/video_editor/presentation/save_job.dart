import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../albums/presentation/albums_providers.dart'
    show nativeChannelProvider;
import '../data/video_cutter.dart';
import '../domain/cut_plan.dart';
import '../domain/save_estimate.dart';

/// The video save under way: the original's name and how far it has got.
@immutable
class SaveJob {
  const SaveJob({required this.name, required this.percent});

  final String name;
  final int percent;
}

final saveJobProvider = NotifierProvider<SaveJobNotifier, SaveJob?>(
  SaveJobNotifier.new,
);

/// The one video save at a time, for the whole app: Android runs it in a
/// service that outlasts any screen, so its state lives here rather than in
/// the dialog showing it. Null while nothing is saving.
class SaveJobNotifier extends Notifier<SaveJob?> {
  late VideoCutter _cutter;
  final Stopwatch _clock = Stopwatch();
  SaveEstimate? _estimate;
  Completer<SavedEdit>? _waiting;

  @override
  SaveJob? build() {
    _cutter = VideoCutter(ref.watch(nativeChannelProvider));
    final StreamSubscription<int> progress = _cutter.progress.listen(_report);
    final StreamSubscription<SaveEnd> ends = _cutter.ends.listen(_end);
    ref.onDispose(() {
      progress.cancel();
      ends.cancel();
    });
    return null;
  }

  /// The time left, or null while it is too soon to say.
  Duration? get left => _estimate?.left;

  /// Saves the parts of video [id] (file [name]) that [plan] keeps, as a
  /// copy or, with [replace], in its place. Completes with the saved video;
  /// throws [CutException], the original untouched.
  Future<SavedEdit> save(
    String id,
    String name,
    CutPlan plan, {
    required bool replace,
  }) async {
    await _cutter.start(id, plan, replace: replace, name: name);
    _clock
      ..reset()
      ..start();
    _estimate = SaveEstimate(() => _clock.elapsed);
    state = SaveJob(name: name, percent: 0);
    final Completer<SavedEdit> done = Completer<SavedEdit>();
    _waiting = done;
    return done.future;
  }

  /// Stops the save while it is still encoding; once saving has begun it
  /// finishes.
  Future<void> cancel() => _cutter.cancel();

  void _report(int percent) {
    final SaveJob? job = state;
    if (job == null) return;
    _estimate?.report(percent);
    state = SaveJob(name: job.name, percent: percent);
  }

  void _end(SaveEnd end) {
    state = null;
    _clock.stop();
    final Completer<SavedEdit>? done = _waiting;
    _waiting = null;
    if (done == null) return;
    final SavedEdit? saved = end.saved;
    saved != null ? done.complete(saved) : done.completeError(end.error!);
  }
}
