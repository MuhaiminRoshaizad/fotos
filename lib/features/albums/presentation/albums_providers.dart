import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/media/read_mode.dart';
import '../../../core/platform/native_channel.dart';

/// The album with [id], looked up fresh so renames and moves show at once.
final albumProvider = FutureProvider.autoDispose.family<Album?, String>((
  Ref ref,
  String id,
) async {
  final List<Album> all = await ref.watch(albumsProvider.future);
  for (final Album a in all) {
    if (a.id == id) return a;
  }
  return null;
});

/// The album's folder as a reading key, for its reading mode.
final albumFolderProvider = FutureProvider.autoDispose.family<String?, String>((
  Ref ref,
  String id,
) async {
  final Album? album = await ref.watch(albumProvider(id).future);
  final String? path = await album?.path.relativePathAsync;
  return path == null ? null : readingKey(path);
});

final albumItemsProvider = FutureProvider.autoDispose
    .family<List<AssetEntity>, String>((Ref ref, String id) async {
      final Album? album = await ref.watch(albumProvider(id).future);
      if (album == null) return <AssetEntity>[];
      return ref.read(mediaRepositoryProvider).albumItems(album);
    });

final nativeChannelProvider = Provider<NativeChannel>(
  (Ref ref) => const NativeChannel(),
);

/// Android's trash, soonest to expire first.
final trashProvider = FutureProvider.autoDispose<List<TrashedItem>>((
  Ref ref,
) async {
  ref.watch(mediaChangesProvider);
  return ref.read(nativeChannelProvider).trash();
});

/// A trashed item's thumbnail, cached while the trash screen is open.
final trashThumbnailProvider = FutureProvider.autoDispose
    .family<Uint8List?, TrashedItem>(
      (Ref ref, TrashedItem item) =>
          ref.read(nativeChannelProvider).trashThumbnail(item, 256),
    );

/// An asset by id, for album covers the user picked.
final assetByIdProvider = FutureProvider.autoDispose
    .family<AssetEntity?, String>(
      (Ref ref, String id) => AssetEntity.fromId(id),
    );
