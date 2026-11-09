import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/native_channel.dart';
import '../../albums/presentation/albums_providers.dart';
import '../data/files_repository.dart';
import '../domain/file_entry.dart';

final filesRepositoryProvider = Provider<FilesRepository>(
  (Ref ref) => FilesRepository(ref.watch(nativeChannelProvider)),
);

class FilesAccessNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(nativeChannelProvider).hasAllFilesAccess();

  /// Called on resume: the user may have just flipped the switch in Settings.
  Future<void> recheck() async {
    final bool now = await ref.read(nativeChannelProvider).hasAllFilesAccess();
    if (state.value != now) state = AsyncData<bool>(now);
  }
}

final filesAccessProvider = AsyncNotifierProvider<FilesAccessNotifier, bool>(
  FilesAccessNotifier.new,
);

final storageRootProvider = FutureProvider<String>(
  (Ref ref) => ref.watch(nativeChannelProvider).storageRoot(),
);

final storageStatsProvider = FutureProvider.autoDispose<StorageStats>(
  (Ref ref) => ref.watch(nativeChannelProvider).storage(),
);

final folderProvider = FutureProvider.autoDispose
    .family<List<FileEntry>, String>(
      (Ref ref, String path) => ref.read(filesRepositoryProvider).list(path),
    );
