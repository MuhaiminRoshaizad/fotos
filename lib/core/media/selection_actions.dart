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
      icon: Icons.share_outlined,
      label: 'Share',
      run: (BuildContext context, Set<String> ids) =>
          ref.read(mediaActionsProvider).share(context, pick(ids)),
    ),
    SelectionAction(
      icon: Icons.add_photo_alternate_outlined,
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
      icon: Icons.favorite_border,
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
      icon: Icons.delete_outline,
      label: 'Delete',
      destructive: true,
      run: (BuildContext context, Set<String> ids) async {
        await ref.read(mediaActionsProvider).trash(context, pick(ids));
        done();
      },
    ),
  ];
}

/// The header that replaces a grid's title while selecting.
class SelectionHeader extends ConsumerWidget {
  const SelectionHeader({super.key, required this.allIds});

  final Set<String> Function() allIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SelectionState s = ref.watch(selectionProvider);
    final int n = s.ids.length;
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Cancel selection',
          onPressed: () => ref.read(selectionProvider.notifier).clear(),
          icon: const Icon(Icons.close),
        ),
        Expanded(
          child: Text(
            n == 1 ? '1 selected' : '$n selected',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: () =>
              ref.read(selectionProvider.notifier).setIds(allIds()),
          child: const Text('Select all'),
        ),
      ],
    );
  }
}
