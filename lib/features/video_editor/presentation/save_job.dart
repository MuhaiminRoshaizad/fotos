import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../albums/presentation/albums_providers.dart'
    show nativeChannelProvider;
import '../data/video_cutter.dart';
import '../domain/cut_plan.dart';
import '../domain/save_estimate.dart';

/// The video save under way: the original's name, how far it has got, and
/// whether it was hidden to run in the background, its end then told by
/// the app rather than by the editor that started it.
@immutable
class SaveJob {
  const SaveJob({
    required this.name,
    required this.percent,
    this.hidden = false,
  });

  final String name;
  final int percent;
  final bool hidden;
}

/// How a hidden save ended, for the app to tell: the original's [name] and
/// the [end] itself.
typedef HiddenEnd = ({String name, SaveEnd end});

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
  Completer<SavedEdit?>? _waiting;
  final StreamController<HiddenEnd> _hiddenEnds =
      StreamController<HiddenEnd>.broadcast();

  @override
  SaveJob? build() {
    _cutter = VideoCutter(ref.watch(nativeChannelProvider));
    final StreamSubscription<int> progress = _cutter.progress.listen(_report);
    final StreamSubscription<SaveEnd> ends = _cutter.ends.listen(_end);
    ref.onDispose(() {
      progress.cancel();
      ends.cancel();
    });
    unawaited(_pickUp());
    return null;
  }

  /// The ends of saves that were hidden, for the app to tell.
  Stream<HiddenEnd> get hiddenEnds => _hiddenEnds.stream;

  /// The time left, or null while it is too soon to say.
  Duration? get left => _estimate?.left;

  /// Starts saving the parts of video [id] (file [name]) that [plan] keeps,
  /// as a copy or, with [replace], in its place. Completes once Android has
  /// started it, with how it will end: the saved video, null if it is
  /// hidden first, or a [CutException], the original untouched. Throws
  /// [CutException] (busy) when a save is already running.
  Future<Future<SavedEdit?>> start(
    String id,
    String name,
    CutPlan plan, {
    required bool replace,
  }) async {
    await _cutter.start(id, plan, replace: replace, name: name);
    _begin(name, 0, hidden: false);
    final Completer<SavedEdit?> done = Completer<SavedEdit?>();
    _waiting = done;
    return done.future;
  }

  /// Leaves the save to run in the background: whoever waits for it hears
  /// null, and its end is told through [hiddenEnds]. Asks for leave to show
  /// notifications, which follow it outside fotos.
  void hide() {
    final SaveJob? job = state;
    if (job == null || job.hidden) return;
    state = SaveJob(name: job.name, percent: job.percent, hidden: true);
    final Completer<SavedEdit?>? waiting = _waiting;
    _waiting = null;
    waiting?.complete(null);
    unawaited(_cutter.askNotifications().catchError((Object _) {}));
  }

  /// Stops the save while it is still encoding; once saving has begun it
  /// finishes.
  Future<void> cancel() => _cutter.cancel();

  /// A fotos opened again while Android was still saving shows that save,
  /// as a hidden one.
  Future<void> _pickUp() async {
    try {
      final SaveStatus? s = await _cutter.status();
      if (s != null && state == null) _begin(s.name, s.percent, hidden: true);
    } on PlatformException {
      // Nothing to pick up.
    } on MissingPluginException {
      // Widget tests run without the Android side.
    }
  }

  void _begin(String name, int percent, {required bool hidden}) {
    _clock
      ..reset()
      ..start();
    _estimate = SaveEstimate(() => _clock.elapsed);
    state = SaveJob(name: name, percent: percent, hidden: hidden);
  }

  void _report(int percent) {
    final SaveJob? job = state;
    if (job == null) return;
    _estimate?.report(percent);
    state = SaveJob(name: job.name, percent: percent, hidden: job.hidden);
  }

  void _end(SaveEnd end) {
    final SaveJob? job = state;
    state = null;
    _clock.stop();
    final Completer<SavedEdit?>? done = _waiting;
    _waiting = null;
    if (done != null) {
      final SavedEdit? saved = end.saved;
      saved != null ? done.complete(saved) : done.completeError(end.error!);
    } else if (job != null && job.hidden) {
      _hiddenEnds.add((name: job.name, end: end));
    }
  }
}
