import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../format/formatters.dart';
import '../haptics/app_haptics.dart';
import '../widgets/dialogs.dart';
import '../widgets/toast.dart';
import '../../features/albums/presentation/albums_providers.dart'
    show nativeChannelProvider;
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
      if (context.mounted) {
        showToast(context, 'Couldn\'t read these files.', failed: true);
      }
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

  /// Whether fotos must ask before deleting, because Android will not.
  ///
  /// Android confirms a trash or delete request itself, except for an app
  /// holding All files access, whose requests it carries out silently. The
  /// Files tab asks for that access, so once it is granted a photo could be
  /// deleted with no question at all. Asking only then avoids two dialogs
  /// in a row on a phone where Android still asks.
  Future<bool> mustConfirmDeletes() =>
      _ref.read(nativeChannelProvider).hasAllFilesAccess();

  /// Moves [items] to Android's trash after a confirmation, and offers
  /// Undo. Returns the ids that were trashed. Pass [confirm] false when
  /// the caller has already asked.
  Future<Set<String>> trash(
    BuildContext context,
    List<AssetEntity> items, {
    bool confirm = true,
  }) async {
    if (items.isEmpty) return <String>{};
    if (confirm && await mustConfirmDeletes()) {
      if (!context.mounted) return <String>{};
      final bool ok = await confirmAction(
        context,
        title: 'Delete ${Fmt.count(items.length, 'item')}?',
        message:
            '${items.length == 1 ? 'It moves' : 'They move'} to Recently '
            'deleted, where you can restore '
            '${items.length == 1 ? 'it' : 'them'} for 30 days.',
        confirmLabel: 'Delete',
      );
      if (!ok) return <String>{};
    }
    final List<String> ids;
    try {
      ids = await _ref.read(mediaRepositoryProvider).moveToTrash(items);
    } on PlatformException catch (e) {
      // Never silent: an item that stays put says why.
      if (context.mounted) {
        showToast(
          context,
          'Couldn\'t delete: ${e.message ?? 'Android refused'}',
          failed: true,
        );
      }
      return <String>{};
    } finally {
      _refresh();
    }
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
