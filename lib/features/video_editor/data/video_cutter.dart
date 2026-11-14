import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../../../core/platform/native_channel.dart';
import '../domain/cut_plan.dart';

/// The video an edit was saved as.
class SavedEdit {
  const SavedEdit({
    required this.id,
    required this.name,
    required this.replaced,
  });

  final String id;
  final String name;

  /// True when the original went to Recently deleted and this took its
  /// place; false when it was saved as a copy beside the original,
  /// including when Android's prompt to replace was declined.
  final bool replaced;
}

/// Why a save did not finish. The original is untouched in every case but
/// [afterTrash]: there it is in Recently deleted, and the edit is kept.
enum CutFailure { noAccess, noSpace, cancelled, busy, failed, afterTrash }

class CutException implements Exception {
  const CutException(this.reason, this.detail);

  final CutFailure reason;
  final String? detail;

  @override
  String toString() => 'CutException($reason, $detail)';
}

/// Saves a [CutPlan] through Android (VideoCutter.kt).
class VideoCutter {
  const VideoCutter(this._native);

  final NativeChannel _native;

  /// Percent done while [plan] saves, by time to encode.
  Stream<int> progressOf(CutPlan plan) {
    final List<int> lengths = <int>[for (final Span s in plan.kept) s.length];
    return _native
        .events('cutProgress')
        .map((Object? p) => byLength(p! as int, lengths));
  }

  /// Encodes the parts of video [id] that [plan] keeps and saves them
  /// beside the original, as a copy or, with [replace], in its place.
  /// Throws [CutException].
  Future<SavedEdit> save(
    String id,
    CutPlan plan, {
    required bool replace,
  }) async {
    try {
      final Map<Object?, Object?> m = (await _native
          .invoke<Map<Object?, Object?>>('cutVideo', <String, Object?>{
            'id': id,
            'keep': <List<int>>[
              for (final Span s in plan.kept) <int>[s.start, s.end],
            ],
            'replace': replace,
          }))!;
      return SavedEdit(
        id: m['id']! as String,
        name: m['name']! as String,
        replaced: m['replaced']! as bool,
      );
    } on PlatformException catch (e) {
      throw CutException(switch (e.code) {
        'no_access' => CutFailure.noAccess,
        'no_space' => CutFailure.noSpace,
        'cancelled' => CutFailure.cancelled,
        'busy' => CutFailure.busy,
        'after_trash' => CutFailure.afterTrash,
        _ => CutFailure.failed,
      }, e.message);
    }
  }

  /// Stops a save that is still encoding. Once saving has begun it finishes.
  Future<void> cancel() => _native.invoke<void>('cutCancel');
}

/// Media3's [progress] for a save of parts [lengths] long, as a share of
/// the whole time to encode.
///
/// Media3 gives every part an equal share of the progress however long it
/// is (SequenceAssetLoader.getProgress in 1.9.2: the parts finished, times
/// 100 over their count, plus the current part's percent over the count).
/// A cut that leaves half a second before it made a save jump to 50% at
/// once and then crawl through the remaining 54 minutes.
@visibleForTesting
int byLength(int progress, List<int> lengths) {
  final int n = lengths.length;
  if (n <= 1 || progress >= 100) return progress;
  final int total = lengths.fold(0, (int sum, int l) => sum + l);
  if (total <= 0) return progress;
  final int index = math.min(n - 1, progress * n ~/ 100);
  final int within = ((progress - index * 100 ~/ n) * n).clamp(0, 100);
  int done = 0;
  for (int i = 0; i < index; i++) {
    done += lengths[i];
  }
  final double share = (done + lengths[index] * within / 100) / total;
  return (share * 100).floor().clamp(0, 99);
}
