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

/// Why a save did not happen. The original is untouched in every case.
enum CutFailure { noAccess, noSpace, cancelled, busy, failed }

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

  /// Percent done while a save runs.
  Stream<int> get progress =>
      _native.events('cutProgress').map((Object? p) => p! as int);

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
        _ => CutFailure.failed,
      }, e.message);
    }
  }

  /// Stops a save that is still encoding. Once saving has begun it finishes.
  Future<void> cancel() => _native.invoke<void>('cutCancel');
}
