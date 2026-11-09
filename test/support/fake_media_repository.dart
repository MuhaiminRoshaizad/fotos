import 'dart:async';

import 'package:fotos/core/media/media_repository.dart';
import 'package:photo_manager/photo_manager.dart';

/// In-memory stand-in for the photo library, for widget tests.
class FakeMediaRepository implements MediaRepository {
  FakeMediaRepository({
    this.accessState = MediaAccess.full,
    this.items = const <AssetEntity>[],
    this.failLoads = false,
    this.grantOnRequest = false,
  });

  MediaAccess accessState;
  List<AssetEntity> items;
  bool failLoads;
  bool grantOnRequest;
  int settingsOpened = 0;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void emitChange() => _changes.add(null);

  Future<List<T>> _load<T>(List<T> v) async {
    if (failLoads) throw StateError('load failed');
    return v;
  }

  @override
  Future<MediaAccess> access() async => accessState;

  @override
  Future<MediaAccess> requestAccess() async {
    if (grantOnRequest) accessState = MediaAccess.full;
    return accessState;
  }

  @override
  Future<void> openAppSettings() async => settingsOpened++;

  @override
  Future<void> pickMoreForLimitedAccess() async {}

  @override
  Future<List<AssetEntity>> library(MediaKind kind) => _load(
    items
        .where(
          (AssetEntity e) => switch (kind) {
            MediaKind.photos => e.type == AssetType.image,
            MediaKind.videos => e.type == AssetType.video,
            MediaKind.all => true,
          },
        )
        .toList(),
  );

  @override
  Future<List<Album>> albums() => _load(<Album>[]);

  @override
  Future<List<AssetEntity>> albumItems(Album album) => _load(items);

  @override
  Future<List<AssetEntity>> favourites() =>
      _load(items.where((AssetEntity e) => e.isFavorite).toList());

  @override
  Stream<void> changes() => _changes.stream;

  @override
  Future<bool> setFavourite(List<AssetEntity> items, bool favourite) async =>
      true;

  @override
  Future<List<String>> moveToTrash(List<AssetEntity> items) async =>
      items.map((AssetEntity e) => e.id).toList();

  @override
  Future<bool> moveTo(List<AssetEntity> items, String relativePath) async =>
      true;

  @override
  Future<int> copyTo(List<AssetEntity> items, String relativePath) async =>
      items.length;
}

AssetEntity fakeAsset(String id, {bool video = false, DateTime? date}) =>
    AssetEntity(
      id: id,
      typeInt: video ? 2 : 1,
      width: 4000,
      height: 3000,
      duration: video ? 42 : 0,
      createDateSecond:
          (date ?? DateTime(2026, 11, 9)).millisecondsSinceEpoch ~/ 1000,
    );
