import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/large_title_scaffold.dart';
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
              BarButton.icon(
                icon: CupertinoIcons.arrow_up_arrow_down,
                tooltip: 'Sort',
                onPressed: () => showSortSheet(context, ref, album),
              ),
              BarButton.icon(
                icon: CupertinoIcons.ellipsis,
                tooltip: 'Album options',
                onPressed: () => showAlbumOptions(context, ref, album),
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

/// A pushed screen holding one media grid: the iOS back button, a large
/// title with the count, Select and optional bar buttons, the grid with
/// selection, and its empty, error and loading states.
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

  /// Bar buttons after Select.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SelectionState sel = ref.watch(selectionProvider);
    final bool selecting = sel.isActiveFor(owner);
    final SelectionNotifier selection = ref.read(selectionProvider.notifier);
    final List<AssetEntity> list = items.value ?? const <AssetEntity>[];
    final int n = sel.ids.length;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) selection.clear();
      },
      child: LargeTitleScaffold(
        title: title,
        subtitle: items.hasValue ? Fmt.count(list.length, 'item') : '',
        barTitle: selecting ? (n == 0 ? 'Select items' : '$n selected') : null,
        leading: selecting
            ? BarButton.text(
                label: 'Select all',
                onPressed: () =>
                    selection.setIds(list.map((AssetEntity e) => e.id).toSet()),
              )
            : const BackBarButton(label: 'Albums'),
        trailing: selecting
            ? <Widget>[
                BarButton.text(
                  label: 'Done',
                  prominent: true,
                  onPressed: selection.clear,
                ),
              ]
            : <Widget>[
                BarButton.text(
                  label: 'Select',
                  onPressed: list.isEmpty
                      ? null
                      : () => selection.start(
                          owner,
                          mediaSelectionActions(ref, () => list),
                        ),
                ),
                ...actions,
              ],
        body: (BuildContext context, Widget header) {
          Widget headed(Widget state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
              Expanded(child: state),
            ],
          );
          return items.when(
            skipLoadingOnRefresh: true,
            loading: () => headed(const GridSkeleton(level: GridLevel.all)),
            error: (_, _) => headed(
              EmptyState(
                icon: CupertinoIcons.exclamationmark_circle,
                title: 'Couldn\'t load $title',
                message: 'Something went wrong reading the photo library.',
                actionLabel: 'Try again',
                onAction: onRetry,
              ),
            ),
            data: (List<AssetEntity> data) => data.isEmpty
                ? headed(
                    EmptyState(
                      icon: CupertinoIcons.rectangle_stack,
                      title: emptyTitle,
                      message: emptyMessage,
                    ),
                  )
                : EntranceScope(
                    child: MediaGrid(
                      animateIn: true,
                      items: data,
                      level: GridLevel.all,
                      grouped: grouped,
                      header: header,
                      overlayTop:
                          MediaQuery.paddingOf(context).top + kBarHeight,
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
          );
        },
      ),
    );
  }
}
