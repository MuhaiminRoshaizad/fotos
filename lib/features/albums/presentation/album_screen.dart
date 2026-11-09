import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/grid_skeleton.dart';
import '../../../core/media/grouping.dart';
import '../../../core/media/media_grid.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/media/selection_actions.dart';
import '../../../core/selection/selection.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../viewer/presentation/viewer_screen.dart';
import '../data/album_prefs.dart';
import 'album_sheets.dart';
import 'albums_providers.dart';

/// One folder's photos and videos, mixed in the album's sort order.
class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.albumId});
  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Album? album = ref.watch(albumProvider(albumId)).value;
    final AlbumSort sort =
        (ref.watch(albumPrefsProvider).value ?? const AlbumPrefs()).sortFor(
          albumId,
        );
    final AsyncValue<List<AssetEntity>> items = ref
        .watch(albumItemsProvider(albumId))
        .whenData(sort.apply);
    return MediaListScreen(
      owner: 'album-$albumId',
      title: album?.name ?? '',
      items: items,
      grouped: sort.groupsByDate,
      onRetry: () => ref.invalidate(albumItemsProvider(albumId)),
      emptyTitle: 'This album is empty',
      emptyMessage: 'Its folder no longer holds any photos or videos.',
      actions: album == null
          ? const <Widget>[]
          : <Widget>[
              IconButton(
                tooltip: 'Sort',
                onPressed: () => showSortSheet(context, ref, album),
                icon: const Icon(Icons.sort),
              ),
              IconButton(
                tooltip: 'Album options',
                onPressed: () => showAlbumOptions(context, ref, album),
                icon: const Icon(Icons.more_vert),
              ),
            ],
    );
  }
}

class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MediaListScreen(
      owner: 'favourites',
      title: 'Favourites',
      items: ref.watch(favouritesProvider),
      grouped: true,
      onRetry: () => ref.invalidate(favouritesProvider),
      emptyTitle: 'No favourites yet',
      emptyMessage: 'Tap the heart on a photo or video to add it here.',
    );
  }
}

/// A pushed screen holding one media grid: back, title, count, optional
/// actions, the grid with selection, and its empty, error and loading states.
class MediaListScreen extends ConsumerWidget {
  const MediaListScreen({
    super.key,
    required this.owner,
    required this.title,
    required this.items,
    required this.grouped,
    required this.onRetry,
    required this.emptyTitle,
    required this.emptyMessage,
    this.actions = const <Widget>[],
  });

  final String owner;
  final String title;
  final AsyncValue<List<AssetEntity>> items;
  final bool grouped;
  final VoidCallback onRetry;
  final String emptyTitle;
  final String emptyMessage;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool selecting = ref.watch(
      selectionProvider.select((SelectionState s) => s.isActiveFor(owner)),
    );
    final List<AssetEntity> list = items.value ?? const <AssetEntity>[];
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) ref.read(selectionProvider.notifier).clear();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !selecting,
          titleSpacing: selecting ? AppSpacing.xs : null,
          title: selecting
              ? SelectionHeader(
                  allIds: () => list.map((AssetEntity e) => e.id).toSet(),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (items.hasValue)
                      Text(
                        Fmt.count(list.length, 'item'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
          actions: selecting ? null : actions,
        ),
        body: items.when(
          skipLoadingOnRefresh: true,
          loading: () => const GridSkeleton(level: GridLevel.all),
          error: (_, _) => EmptyState(
            icon: Icons.error_outline,
            title: 'Couldn\'t load $title',
            message: 'Something went wrong reading the photo library.',
            actionLabel: 'Try again',
            onAction: onRetry,
          ),
          data: (List<AssetEntity> data) => data.isEmpty
              ? EmptyState(
                  icon: Icons.photo_album_outlined,
                  title: emptyTitle,
                  message: emptyMessage,
                )
              : MediaGrid(
                  items: data,
                  level: GridLevel.all,
                  grouped: grouped,
                  heroPrefix: owner,
                  selectionOwner: owner,
                  selectionActions: () =>
                      mediaSelectionActions(ref, () => data),
                  onOpen: (int index) => context.push(
                    '/viewer',
                    extra: ViewerArgs(
                      items: data,
                      index: index,
                      heroPrefix: owner,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
