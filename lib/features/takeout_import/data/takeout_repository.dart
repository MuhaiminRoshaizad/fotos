import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/native_channel.dart';
import '../../albums/presentation/albums_providers.dart';
import '../domain/takeout_models.dart';

/// The Takeout import, run natively (TakeoutImporter.kt) and reported here.
class TakeoutRepository {
  const TakeoutRepository(this._native);

  final NativeChannel _native;

  Stream<TakeoutCounts> progress() => _native
      .events('takeoutProgress')
      .map((Object? a) => TakeoutCounts.fromMap(a! as Map<Object?, Object?>));

  /// Runs until done or cancelled; resumes a previous run of the same ZIP.
  /// Throws [NotEnoughSpaceException] before writing anything if room is short.
  Future<TakeoutCounts> run(String zipPath) async {
    try {
      final Map<Object?, Object?>? m = await _native
          .invoke<Map<Object?, Object?>>('takeoutStart', <String, Object?>{
            'path': zipPath,
          });
      return TakeoutCounts.fromMap(m!);
    } on PlatformException catch (e) {
      final String msg = e.message ?? '';
      if (msg.startsWith('not_enough_space:')) {
        throw NotEnoughSpaceException(int.parse(msg.split(':').last));
      }
      rethrow;
    }
  }

  Future<void> cancel() => _native.invoke<void>('takeoutCancel');

  Future<List<ReviewItem>> reviews() async {
    final List<Object?>? rows = await _native.invoke<List<Object?>>(
      'takeoutReviews',
    );
    return <ReviewItem>[
      for (final Object? r in rows ?? <Object?>[])
        ReviewItem.fromMap(r! as Map<Object?, Object?>),
    ];
  }

  /// Keep the Takeout copy (publish it) or drop it; the staged file goes
  /// either way.
  Future<void> resolve(ReviewItem item, {required bool keepTakeout}) =>
      _native.invoke<void>('takeoutResolve', <String, Object?>{
        'id': item.id,
        'keepTakeout': keepTakeout,
      });
}

final takeoutRepositoryProvider = Provider<TakeoutRepository>(
  (Ref ref) => TakeoutRepository(ref.watch(nativeChannelProvider)),
);

final reviewsProvider = FutureProvider.autoDispose<List<ReviewItem>>(
  (Ref ref) => ref.read(takeoutRepositoryProvider).reviews(),
);
