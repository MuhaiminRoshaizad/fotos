import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../format/formatters.dart';
import '../haptics/app_haptics.dart';
import '../widgets/toast.dart';
import 'media_providers.dart';

/// The edits offered both in the viewer and on the selection bar, so each
/// behaves the same wherever it is used.
class MediaActions {
  const MediaActions(this._ref);

  final Ref _ref;

  void _refresh() {
    _ref.invalidate(libraryProvider);
    _ref.invalidate(albumsProvider);
    _ref.invalidate(favouritesProvider);
  }

  Future<void> share(BuildContext context, List<AssetEntity> items) async {
    final List<XFile> files = <XFile>[];
    for (final AssetEntity e in items) {
      final File? f = await e.originFile;
      if (f != null) files.add(XFile(f.path, mimeType: e.mimeType));
    }
    if (files.isEmpty) {
      if (context.mounted) showToast(context, 'Couldn\'t read these files.');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: files));
  }

  /// Returns whether Android applied the change.
  Future<bool> setFavourite(
    BuildContext context,
    List<AssetEntity> items,
    bool favourite,
  ) async {
    final bool ok = await _ref
        .read(mediaRepositoryProvider)
        .setFavourite(items, favourite);
    if (ok && favourite) AppHaptics.light();
    _refresh();
    if (context.mounted && items.length > 1) {
      showToast(
        context,
        ok
            ? '${favourite ? 'Added' : 'Removed'} ${Fmt.count(items.length, 'item')} '
                  '${favourite ? 'to' : 'from'} Favourites'
            : 'Favourites weren\'t changed.',
      );
    }
    return ok;
  }

  /// Moves [items] to Android's trash after its own confirmation, and offers
  /// Undo. Returns the ids that were trashed.
  Future<Set<String>> trash(
    BuildContext context,
    List<AssetEntity> items,
  ) async {
    final List<String> ids = await _ref
        .read(mediaRepositoryProvider)
        .moveToTrash(items);
    _refresh();
    if (ids.isEmpty) return <String>{};
    final List<AssetEntity> trashed = items
        .where((AssetEntity e) => ids.contains(e.id))
        .toList();
    if (context.mounted) {
      showToast(
        context,
        'Moved ${Fmt.count(trashed.length, 'item')} to trash',
        actionLabel: 'Undo',
        onAction: () async {
          await _ref.read(mediaRepositoryProvider).restoreFromTrash(trashed);
          _refresh();
        },
      );
    }
    return ids.toSet();
  }
}

final Provider<MediaActions> mediaActionsProvider = Provider<MediaActions>(
  MediaActions.new,
);
