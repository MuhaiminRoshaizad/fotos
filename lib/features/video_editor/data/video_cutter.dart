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
  /// including when Android would not trash the original.
  final bool replaced;
}

/// Why a save did not finish. The original is untouched in every case.
enum CutFailure { noAccess, noSpace, cancelled, busy, failed }

class CutException implements Exception {
  const CutException(this.reason, this.detail);

  final CutFailure reason;
  final String? detail;

  @override
  String toString() => 'CutException($reason, $detail)';
}

/// How a save ended: [saved], or [error].
class SaveEnd {
  const SaveEnd.saved(SavedEdit this.saved) : error = null;
  const SaveEnd.failed(CutException this.error) : saved = null;

  final SavedEdit? saved;
  final CutException? error;
}

/// Saves a [CutPlan] through Android, where SaveService runs it
/// (VideoCutter.kt) so it carries on with fotos in the background. One
/// save runs at a time; its progress and end arrive as events.
class VideoCutter {
  const VideoCutter(this._native);

  final NativeChannel _native;

  /// Percent done of the save under way, by time to encode.
  Stream<int> get progress =>
      _native.events('cutProgress').map((Object? p) => p! as int);

  /// The end of each save.
  Stream<SaveEnd> get ends => _native
      .events('cutDone')
      .map((Object? m) => endOf(m! as Map<Object?, Object?>));

  /// Starts encoding the parts of video [id] that [plan] keeps, to be saved
  /// beside the original, as a copy or, with [replace], in its place.
  /// [name] is the original's file name, for the notification. Throws
  /// [CutException] (busy) when a save is already running.
  Future<void> start(
    String id,
    CutPlan plan, {
    required bool replace,
    required String name,
  }) async {
    try {
      await _native.invoke<void>('cutVideo', <String, Object?>{
        'id': id,
        'keep': <List<int>>[
          for (final Span s in plan.kept) <int>[s.start, s.end],
        ],
        'replace': replace,
        'name': name,
      });
    } on PlatformException catch (e) {
      throw CutException(reasonOf(e.code), e.message);
    }
  }

  /// Stops a save that is still encoding. Once saving has begun it finishes.
  Future<void> cancel() => _native.invoke<void>('cutCancel');
}

/// The reason Android gave as [code].
CutFailure reasonOf(String code) => switch (code) {
  'no_access' => CutFailure.noAccess,
  'no_space' => CutFailure.noSpace,
  'cancelled' => CutFailure.cancelled,
  'busy' => CutFailure.busy,
  _ => CutFailure.failed,
};

/// A cutDone event: the new video's id, name and whether it replaced the
/// original, or an error code and message.
SaveEnd endOf(Map<Object?, Object?> m) {
  final Object? error = m['error'];
  if (error is String) {
    return SaveEnd.failed(
      CutException(reasonOf(error), m['message'] as String?),
    );
  }
  return SaveEnd.saved(
    SavedEdit(
      id: m['id']! as String,
      name: m['name']! as String,
      replaced: m['replaced']! as bool,
    ),
  );
}
