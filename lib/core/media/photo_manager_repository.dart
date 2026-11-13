import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../platform/native_channel.dart';
import 'media_repository.dart';

/// [MediaRepository] over Android's MediaStore, through photo_manager.
class PhotoManagerRepository implements MediaRepository {
  PhotoManagerRepository([this._native = const NativeChannel()]);

  final NativeChannel _native;

  static const PermissionRequestOption _permission = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      // Lets the details sheet read where a photo was taken.
      mediaLocation: true,
    ),
  );

  static const int _pageSize = 500;

  /// Newest first by when the photo was taken, not when it reached the
  /// phone, so imported Takeout items land in their real months. Items with
  /// no date taken (WhatsApp, Telegram, downloads) sort by when they were
  /// added: the same fallback photo_manager uses for `createDateTime`, which
  /// the grid's month headings read. Sorting on `datetaken` alone put those
  /// items after everything else, so months repeated further down the grid.
  static CustomFilter _filter(String where) => CustomFilter.sql(
    where: where,
    orderBy: const <OrderByItem>[
      OrderByItem.desc('COALESCE(NULLIF(datetaken, 0), date_added * 1000)'),
      OrderByItem.desc('_id'),
    ],
  )..needTitle = true;

  static String _typeWhere(MediaKind kind) => switch (kind) {
    MediaKind.photos => 'media_type = 1',
    MediaKind.videos => 'media_type = 3',
    MediaKind.all => 'media_type IN (1, 3)',
  };

  static RequestType _request(MediaKind kind) => switch (kind) {
    MediaKind.photos => RequestType.image,
    MediaKind.videos => RequestType.video,
    MediaKind.all => RequestType.common,
  };

  static MediaAccess _map(PermissionState s) => switch (s) {
    PermissionState.authorized => MediaAccess.full,
    PermissionState.limited => MediaAccess.limited,
    _ => MediaAccess.denied,
  };

  @override
  Future<MediaAccess> access() async =>
      _map(await PhotoManager.getPermissionState(requestOption: _permission));

  @override
  Future<MediaAccess> requestAccess() async => _map(
    await PhotoManager.requestPermissionExtend(requestOption: _permission),
  );

  @override
  Future<void> openAppSettings() => PhotoManager.openSetting();

  @override
  Future<void> pickMoreForLimitedAccess() => PhotoManager.presentLimited();

  Future<List<AssetEntity>> _all(AssetPathEntity path) async {
    final int count = await path.assetCountAsync;
    final List<AssetEntity> out = <AssetEntity>[];
    for (int start = 0; start < count; start += _pageSize) {
      out.addAll(
        await path.getAssetListRange(start: start, end: start + _pageSize),
      );
    }
    return out;
  }

  Future<List<AssetEntity>> _query(MediaKind kind, String where) async {
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: _request(kind),
      filterOption: _filter(
        where.isEmpty ? _typeWhere(kind) : '${_typeWhere(kind)} AND $where',
      ),
    );
    if (paths.isEmpty) return <AssetEntity>[];
    return _all(paths.first);
  }

  @override
  Future<List<AssetEntity>> library(MediaKind kind) => _query(kind, '');

  @override
  Future<List<AssetEntity>> favourites() =>
      _query(MediaKind.all, 'is_favorite = 1');

  @override
  Future<List<Album>> albums() async {
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      hasAll: false,
      type: RequestType.common,
      filterOption: _filter(_typeWhere(MediaKind.all)),
    );
    final List<Album> out = <Album>[];
    for (final AssetPathEntity p in paths) {
      final int count = await p.assetCountAsync;
      if (count == 0) continue;
      final List<AssetEntity> first = await p.getAssetListRange(
        start: 0,
        end: 1,
      );
      out.add(
        Album(
          id: p.id,
          name: p.name,
          count: count,
          path: p,
          cover: first.isEmpty ? null : first.first,
        ),
      );
    }
    return out;
  }

  @override
  Future<List<AssetEntity>> albumItems(Album album) => _all(album.path);

  @override
  Stream<void> changes() {
    late final StreamController<void> controller;
    void onChange(MethodCall _) => controller.add(null);
    controller = StreamController<void>.broadcast(
      onListen: () {
        PhotoManager.addChangeCallback(onChange);
        PhotoManager.startChangeNotify();
      },
      onCancel: () {
        PhotoManager.removeChangeCallback(onChange);
        PhotoManager.stopChangeNotify();
      },
    );
    return controller.stream;
  }

  @override
  Future<bool> setFavourite(List<AssetEntity> items, bool favourite) =>
      // photo_manager asks once per item; this asks once for the batch.
      _native.favourite(
        items.map((AssetEntity e) => e.id).toList(),
        items.map((AssetEntity e) => e.type == AssetType.video).toList(),
        value: favourite,
      );

  @override
  Future<List<String>> moveToTrash(List<AssetEntity> items) =>
      // photo_manager looks each item up first and fails the whole request
      // when one's file is missing; fotos builds the request itself.
      _native.setTrashed(
        items.map((AssetEntity e) => e.id).toList(),
        items.map((AssetEntity e) => e.type == AssetType.video).toList(),
        value: true,
      );

  @override
  Future<List<String>> restoreFromTrash(List<AssetEntity> items) =>
      _native.setTrashed(
        items.map((AssetEntity e) => e.id).toList(),
        items.map((AssetEntity e) => e.type == AssetType.video).toList(),
        value: false,
      );

  @override
  Future<String?> folderOf(Album album) => album.path.relativePathAsync;

  @override
  Future<bool> moveTo(List<AssetEntity> items, String relativePath) =>
      PhotoManager.editor.android.moveAssetsToPath(
        entities: items,
        targetPath: relativePath,
      );

  @override
  Future<int> copyTo(List<AssetEntity> items, String relativePath) async {
    int copied = 0;
    for (final AssetEntity e in items) {
      final File? file = await e.originFile;
      if (file == null) continue;
      if (e.type == AssetType.video) {
        await PhotoManager.editor.saveVideo(
          file,
          title: e.title,
          relativePath: relativePath,
          creationDate: e.createDateTime,
        );
      } else {
        await PhotoManager.editor.saveImageWithPath(
          file.path,
          title: e.title,
          relativePath: relativePath,
          creationDate: e.createDateTime,
        );
      }
      copied++;
    }
    return copied;
  }
}
