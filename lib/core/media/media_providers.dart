import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import 'media_repository.dart';
import 'photo_manager_repository.dart';

final Provider<MediaRepository> mediaRepositoryProvider =
    Provider<MediaRepository>((Ref ref) => PhotoManagerRepository());

class MediaAccessNotifier extends AsyncNotifier<MediaAccess> {
  @override
  Future<MediaAccess> build() => ref.watch(mediaRepositoryProvider).access();

  Future<void> request() async {
    state = AsyncData<MediaAccess>(
      await ref.read(mediaRepositoryProvider).requestAccess(),
    );
  }

  /// Called when the app returns from Settings, where access may have changed.
  Future<void> recheck() async {
    final MediaAccess now = await ref.read(mediaRepositoryProvider).access();
    if (state.value != now) state = AsyncData<MediaAccess>(now);
  }
}

final AsyncNotifierProvider<MediaAccessNotifier, MediaAccess>
mediaAccessProvider = AsyncNotifierProvider<MediaAccessNotifier, MediaAccess>(
  MediaAccessNotifier.new,
);

/// Ticks whenever the device library changes; lists watch it to refresh.
/// A burst (a 300-item move, a running Takeout import) arrives as one tick
/// once the library has been quiet for a moment, so the whole library isn't
/// re-read after every single file.
final StreamProvider<int> mediaChangesProvider = StreamProvider<int>((Ref ref) {
  final StreamController<int> out = StreamController<int>();
  int ticks = 0;
  Timer? debounce;
  final StreamSubscription<void> sub = ref
      .watch(mediaRepositoryProvider)
      .changes()
      .listen((_) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 1500), () {
          out.add(++ticks);
        });
      });
  out.add(ticks);
  ref.onDispose(() {
    debounce?.cancel();
    sub.cancel();
    out.close();
  });
  return out.stream;
});

/// Reads that need access first; empty while access is denied.
Future<List<T>> _withAccess<T>(Ref ref, Future<List<T>> Function() load) async {
  ref.watch(mediaChangesProvider);
  final MediaAccess access = await ref.watch(mediaAccessProvider.future);
  if (access == MediaAccess.denied) return <T>[];
  return load();
}

final libraryProvider = FutureProvider.family<List<AssetEntity>, MediaKind>(
  (Ref ref, MediaKind kind) =>
      _withAccess(ref, () => ref.read(mediaRepositoryProvider).library(kind)),
);

final FutureProvider<List<Album>> albumsProvider = FutureProvider<List<Album>>(
  (Ref ref) =>
      _withAccess(ref, () => ref.read(mediaRepositoryProvider).albums()),
);

final FutureProvider<List<AssetEntity>> favouritesProvider =
    FutureProvider<List<AssetEntity>>(
      (Ref ref) => _withAccess(
        ref,
        () => ref.read(mediaRepositoryProvider).favourites(),
      ),
    );
