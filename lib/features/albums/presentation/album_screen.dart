import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSlidingSegmentedControl;
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
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/scroll_handle.dart';
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
    final AsyncValue<List<AssetEntity>> items = ref.watch(
      sortedAlbumItemsProvider(albumId),
    );
    return MediaListScreen(
      owner: 'album-$albumId',
      title: album?.name ?? '',
      readingFolder: ref.watch(albumFolderProvider(albumId)).value,
      items: items,
      grouped: sort.groupsByDate,
      orderLabel: _orderLabel(sort.by),
      onRetry: () => ref.invalidate(albumItemsProvider(albumId)),
      emptyTitle: 'This album is empty',
      emptyMessage: 'Its folder no longer holds any photos or videos.',
      actions: album == null
          ? const <Widget>[]
          : <Widget>[
              // Sort lives in this menu with the other album options.
              BarButton.icon(
                icon: CupertinoIcons.ellipsis,
                tooltip: 'Album options',
                onPressed: () async {
                  final Album? renamed = await showAlbumOptions(
                    context,
                    ref,
                    album,
                  );
                  // A renamed folder has a new id, so this page follows it.
                  if (renamed != null && context.mounted) {
                    context.replace('/albums/folder/${renamed.id}');
                  }
                },
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
/// selection, and its empty, error and loading states. A list holding both
/// photos and videos gets a switch under its title to show only one kind.
class MediaListScreen extends ConsumerStatefulWidget {
  const MediaListScreen({
    super.key,
    required this.owner,
    required this.title,
    required this.items,
    required this.grouped,
    this.orderLabel,
    required this.onRetry,
    required this.emptyTitle,
    required this.emptyMessage,
    this.actions = const <Widget>[],
    this.readingFolder,
  });

  final String owner;
  final String title;
  final AsyncValue<List<AssetEntity>> items;
  final bool grouped;

  /// The scroll handle's label when [grouped] is false; see
  /// [MediaGrid.orderLabel].
  final HandleLabel Function(AssetEntity item, int index, int count)?
  orderLabel;
  final VoidCallback onRetry;
  final String emptyTitle;
  final String emptyMessage;

  /// Bar buttons after Select.
  final List<Widget> actions;

  /// The folder these come from, as a reading key, so the viewer can
  /// read them as pages or a strip; null for a mixed list.
  final String? readingFolder;

  @override
  ConsumerState<MediaListScreen> createState() => _MediaListScreenState();
}

/// Which kind of item a mixed list shows.
enum MediaShown {
  all('All', 'item', null),
  photos('Photos', 'photo', AssetType.image),
  videos('Videos', 'video', AssetType.video);

  const MediaShown(this.label, this.noun, this.type);

  final String label;

  /// What the count under the title counts.
  final String noun;

  /// Null shows every item.
  final AssetType? type;

  List<AssetEntity> apply(List<AssetEntity> items) => type == null
      ? items
      : items.where((AssetEntity e) => e.type == type).toList();
}

class _MediaListScreenState extends ConsumerState<MediaListScreen>
    with SingleTickerProviderStateMixin {
  /// What the switch shows, at once, so its thumb slides on the tap.
  MediaShown _picked = MediaShown.all;

  /// What the grid shows: [_picked] once the old tiles have faded out.
  /// Not saved; the list opens on All every time, so a kind left hidden
  /// can't seem to go missing later.
  MediaShown _shown = MediaShown.all;

  /// The page colour drawn over the tiles (not the title or the switch)
  /// while they change: the old ones fade out, then the new ones in.
  late final AnimationController _curtain;
  double _curtainTop = 0;
  final GlobalKey _switch = GlobalKey();
  final GlobalKey _body = GlobalKey();

  @override
  void initState() {
    super.initState();
    _curtain = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _curtain.dispose();
    super.dispose();
  }

  Future<void> _pick(MediaShown next) async {
    if (next == _picked) return;
    setState(() => _picked = next);
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _shown = next);
      return;
    }
    final RenderBox? sw =
        _switch.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? body =
        _body.currentContext?.findRenderObject() as RenderBox?;
    if (sw != null && body != null) {
      _curtainTop = sw
          .localToGlobal(Offset(0, sw.size.height), ancestor: body)
          .dy;
    }
    await _curtain.animateTo(
      1,
      duration: AppMotion.short,
      curve: Curves.easeIn,
    );
    if (!mounted) return;
    // After a second tap meanwhile, show where the switch ended up.
    setState(() => _shown = _picked);
    await _curtain.animateTo(
      0,
      duration: AppMotion.medium,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final SelectionState sel = ref.watch(selectionProvider);
    final bool selecting = sel.isActiveFor(widget.owner);
    final SelectionNotifier selection = ref.read(selectionProvider.notifier);
    final List<AssetEntity> all = widget.items.value ?? const <AssetEntity>[];
    // Only a list holding both kinds can be narrowed to one.
    final bool mixed =
        all.any((AssetEntity e) => e.type == AssetType.image) &&
        all.any((AssetEntity e) => e.type == AssetType.video);
    final MediaShown shown = mixed ? _shown : MediaShown.all;
    final List<AssetEntity> list = shown.apply(all);
    final int n = sel.ids.length;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) selection.clear();
      },
      child: LargeTitleScaffold(
        title: widget.title,
        subtitle: widget.items.hasValue
            ? Fmt.count(list.length, shown.noun)
            : '',
        barTitle: selecting ? (n == 0 ? 'Select items' : '$n selected') : null,
        // Collapsed, the bar says the list is narrowed, so it is never
        // mistaken for a short one.
        barSubtitle: shown.type == null ? null : '${shown.label} only',
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
                          widget.owner,
                          mediaSelectionActions(ref, () => list),
                        ),
                ),
                ...widget.actions,
              ],
        body: (BuildContext context, Widget header) {
          Widget headed(Widget state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
              Expanded(child: state),
            ],
          );
          return widget.items.when(
            // A delete or move reads the library again, and the album with it;
            // the skeleton would replace the grid and lose the scroll position.
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => headed(const GridSkeleton(level: GridLevel.all)),
            error: (_, _) => headed(
              EmptyState(
                icon: CupertinoIcons.exclamationmark_circle,
                title: 'Couldn\'t load ${widget.title}',
                message: 'Something went wrong reading the photo library.',
                actionLabel: 'Try again',
                onAction: widget.onRetry,
              ),
            ),
            data: (List<AssetEntity> data) => data.isEmpty
                ? headed(
                    EmptyState(
                      icon: CupertinoIcons.rectangle_stack,
                      title: widget.emptyTitle,
                      message: widget.emptyMessage,
                    ),
                  )
                : Stack(
                    key: _body,
                    fit: StackFit.expand,
                    children: <Widget>[
                      EntranceScope(
                        child: MediaGrid(
                          animateIn: true,
                          items: list,
                          level: GridLevel.all,
                          grouped: widget.grouped,
                          orderLabel: widget.orderLabel,
                          header: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              header,
                              if (mixed)
                                _ShownSwitch(
                                  key: _switch,
                                  value: _picked,
                                  enabled: !selecting,
                                  onChanged: _pick,
                                ),
                            ],
                          ),
                          overlayTop:
                              MediaQuery.paddingOf(context).top + kBarHeight,
                          heroPrefix: widget.owner,
                          selectionOwner: widget.owner,
                          selectionActions: () =>
                              mediaSelectionActions(ref, () => list),
                          onOpen: (int index, RevealItem reveal) =>
                              context.push(
                                '/viewer',
                                extra: ViewerArgs(
                                  items: list,
                                  index: index,
                                  heroPrefix: widget.owner,
                                  folder: widget.readingFolder,
                                  title: widget.title,
                                  onShow: reveal,
                                ),
                              ),
                        ),
                      ),
                      Positioned(
                        top: _curtainTop,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: FadeTransition(
                            opacity: _curtain,
                            child: ColoredBox(
                              color: Theme.of(context).colorScheme.surface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// All, Photos or Videos, under a mixed list's title. Dimmed and still
/// while selecting, so a selection never holds items it no longer shows.
class _ShownSwitch extends StatelessWidget {
  const _ShownSwitch({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final MediaShown value;
  final bool enabled;
  final ValueChanged<MediaShown> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xs,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    child: IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.4,
        duration: AppMotion.short,
        child: CupertinoSlidingSegmentedControl<MediaShown>(
          groupValue: value,
          children: <MediaShown, Widget>{
            for (final MediaShown s in MediaShown.values)
              s: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(s.label),
              ),
          },
          onValueChanged: (MediaShown? v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    ),
  );
}

/// What an album's scroll handle says when it is sorted by name (how far
/// in, as a comic's pages are named 001.jpg on) or by length (the video's
/// length, marked in bands). Sorted by date it shows the date instead.
HandleLabel Function(AssetEntity item, int index, int count)? _orderLabel(
  AlbumSortBy by,
) => switch (by) {
  AlbumSortBy.taken => null,
  AlbumSortBy.name => (AssetEntity item, int index, int count) => HandleLabel(
    '${index + 1}',
    secondary: 'of $count',
  ),
  AlbumSortBy.length =>
    (AssetEntity item, int index, int count) => item.type == AssetType.video
        ? HandleLabel(
            Fmt.duration(Duration(seconds: item.duration)),
            secondary: 'long',
            mark: switch (item.duration) {
              >= 600 => 'Over 10 min',
              >= 60 => '1 to 10 min',
              _ => 'Under 1 min',
            },
          )
        : const HandleLabel('Photo', mark: 'Photos'),
};
