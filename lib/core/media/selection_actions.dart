import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../selection/selection.dart';
import 'add_to_album.dart';
import 'media_actions.dart';

/// The selection bar for any media grid: Share, Add to album, Favourite and
/// Delete. [source] resolves the selected ids against what is on screen.
List<SelectionAction> mediaSelectionActions(
  WidgetRef ref,
  List<AssetEntity> Function() source, {
  void Function(String albumName)? onViewAlbum,
}) {
  List<AssetEntity> pick(Set<String> ids) =>
      source().where((AssetEntity e) => ids.contains(e.id)).toList();
  void done() => ref.read(selectionProvider.notifier).clear();

  return <SelectionAction>[
    SelectionAction(
      icon: CupertinoIcons.square_arrow_up,
      label: 'Share',
      run: (BuildContext context, Set<String> ids) =>
          ref.read(mediaActionsProvider).share(context, pick(ids)),
    ),
    SelectionAction(
      icon: CupertinoIcons.plus_rectangle_on_rectangle,
      label: 'Add to album',
      run: (BuildContext context, Set<String> ids) => addToAlbum(
        context,
        ref,
        pick(ids),
        onDone: done,
        onView: onViewAlbum,
      ),
    ),
    SelectionAction(
      icon: CupertinoIcons.heart,
      label: 'Favourite',
      run: (BuildContext context, Set<String> ids) async {
        final List<AssetEntity> items = pick(ids);
        // All already favourites: the same button takes them out again.
        final bool on = !items.every((AssetEntity e) => e.isFavorite);
        await ref.read(mediaActionsProvider).setFavourite(context, items, on);
        done();
      },
    ),
    SelectionAction(
      icon: CupertinoIcons.trash,
      label: 'Delete',
      destructive: true,
      run: (BuildContext context, Set<String> ids) async {
        await ref.read(mediaActionsProvider).trash(context, pick(ids));
        done();
      },
    ),
  ];
}
