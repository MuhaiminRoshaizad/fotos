import 'package:photo_manager/photo_manager.dart';

/// What the user has allowed fotos to see in the photo library.
enum MediaAccess {
  /// Every photo and video.
  full,

  /// Android 14+ "Select photos": only the items the user picked.
  limited,

  /// Refused, or not asked yet.
  denied,
}

enum MediaKind { photos, videos, all }

/// A folder that holds media, as Android's photo library groups it.
class Album {
  const Album({
    required this.id,
    required this.name,
    required this.count,
    required this.path,
    this.cover,
  });

  final String id;
  final String name;
  final int count;
  final AssetPathEntity path;
  final AssetEntity? cover;
}

/// The phone's photo library. Items are newest first by date taken.
///
/// The interface hands out [AssetEntity] directly instead of a fotos model:
/// the thumbnail and viewer image providers need the entity itself, and a
/// mirror class would duplicate every field for no second implementation.
abstract interface class MediaRepository {
  Future<MediaAccess> access();
  Future<MediaAccess> requestAccess();
  Future<void> openAppSettings();

  /// Lets a user on limited access add more items to what fotos can see.
  Future<void> pickMoreForLimitedAccess();

  Future<List<AssetEntity>> library(MediaKind kind);
  Future<List<Album>> albums();
  Future<List<AssetEntity>> albumItems(Album album);
  Future<List<AssetEntity>> favourites();

  /// Fires whenever the library changes on the device.
  Stream<void> changes();

  /// Each returns the ids Android actually changed; the user can refuse the
  /// system confirmation, in which case nothing changes.
  Future<bool> setFavourite(List<AssetEntity> items, bool favourite);
  Future<List<String>> moveToTrash(List<AssetEntity> items);
  Future<List<String>> restoreFromTrash(List<AssetEntity> items);
  Future<bool> moveTo(List<AssetEntity> items, String relativePath);

  /// [album]'s folder inside shared storage, such as "Pictures/Trip/".
  Future<String?> folderOf(Album album);
  Future<int> copyTo(List<AssetEntity> items, String relativePath);
}
