import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/add_to_album.dart';
import '../../../core/media/empty_albums.dart';
import '../../../core/media/media_access_gate.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/lift_menu.dart';
import '../data/album_prefs.dart';
import 'album_sheets.dart';
import 'albums_providers.dart';
import 'new_album.dart';

/// The Albums tab: pinned albums first, then every folder holding media, then
/// Favourites, Recently deleted and the Takeout import as grouped rows.
class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LargeTitleScaffold(
      title: 'Albums',
      grouped: true,
      trailing: <Widget>[
        BarButton.icon(
          icon: CupertinoIcons.plus,
          tooltip: 'New album',
          onPressed: () => createAlbum(context, ref),
        ),
      ],
      body: (BuildContext context, Widget header) => MediaAccessGate(
        header: header,
        builder: (Widget h) => _AlbumsBody(header: h),
      ),
    );
  }
}

class _AlbumsBody extends ConsumerWidget {
  const _AlbumsBody({required this.header});

  final Widget header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Album>> albums = ref.watch(albumsProvider);
    final AlbumPrefs prefs =
        ref.watch(albumPrefsProvider).value ?? const AlbumPrefs();
    final List<String> empty =
        ref.watch(emptyAlbumsProvider).value ?? const <String>[];
    final double bottom = AppNavMetrics.clearance(
      MediaQuery.paddingOf(context).bottom,
    );
    Widget headed(Widget state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        Expanded(child: state),
      ],
    );
    return albums.when(
      skipLoadingOnRefresh: true,
      loading: () => headed(const _AlbumsSkeleton()),
      error: (_, _) => headed(
        EmptyState(
          icon: CupertinoIcons.exclamationmark_circle,
          title: 'Couldn\'t load your albums',
          message: 'Something went wrong reading the photo library.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(albumsProvider),
        ),
      ),
      data: (List<Album> list) {
        final List<Album> pinned = <Album>[
          for (final String id in prefs.pinned)
            ...list.where((Album a) => a.id == id),
        ];
        final List<Album> rest = list
            .where((Album a) => !prefs.pinned.contains(a.id))
            .toList();
        final List<String> pending = pendingEmptyAlbums(empty, list);
        if (pending.length != empty.length) {
          // An empty album that now holds something is a real folder; forget
          // the placeholder so deleting that folder later doesn't revive it.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final String n in empty.where(
              (String n) => !pending.contains(n),
            )) {
              ref.read(emptyAlbumsProvider.notifier).remove(n);
            }
          });
        }
        final int favourites = ref.watch(favouritesProvider).value?.length ?? 0;
        final int trashed = ref.watch(trashProvider).value?.length ?? 0;
        return CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(child: header),
            if (pinned.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(child: GroupHeading('Pinned')),
              _AlbumGrid(albums: pinned, prefs: prefs),
            ],
            const SliverToBoxAdapter(child: GroupHeading('On this phone')),
            if (list.isEmpty && pending.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text('No folders with photos or videos yet.'),
                ),
              )
            else
              _AlbumGrid(albums: rest, prefs: prefs, empty: pending),
            SliverToBoxAdapter(
              child: InsetGroup(
                header: 'Library',
                children: <Widget>[
                  GroupRow(
                    leading: const Icon(CupertinoIcons.heart),
                    title: 'Favourites',
                    value: favourites == 0 ? null : '$favourites',
                    onTap: () => context.push('/albums/favourites'),
                  ),
                  GroupRow(
                    leading: const Icon(CupertinoIcons.trash),
                    title: 'Recently deleted',
                    value: trashed == 0 ? null : '$trashed',
                    onTap: () => context.push('/albums/trash'),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: InsetGroup(
                header: 'Bring photos home',
                footer:
                    'Pick the ZIPs from your Takeout export. Locked Folder '
                    'items are skipped and counted.',
                children: <Widget>[
                  GroupRow(
                    leading: const Icon(CupertinoIcons.arrow_down_circle),
                    title: 'Import from Google Takeout',
                    onTap: () => context.push('/albums/takeout'),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        );
      },
    );
  }
}

/// Columns of album tiles at this screen width: two on phones, more on
/// tablets so covers stay a sensible size.
int _albumColumns(BuildContext context) {
  final double width = MediaQuery.sizeOf(context).width;
  return width >= 900 ? 5 : (width >= 600 ? 4 : 2);
}

/// Height of one album tile: the square cover plus two lines of text at the
/// user's text size. A fixed aspect ratio overflowed at large text sizes.
double _albumTileExtent(BuildContext context, int columns) {
  final double width = MediaQuery.sizeOf(context).width;
  final double cover =
      (width - AppSpacing.lg * 2 - AppSpacing.md * (columns - 1)) / columns;
  final TextScaler s = MediaQuery.textScalerOf(context);
  // Name (14 on a 20 line) and count (13 on a 19 line).
  final double text = s.scale(14) / 14 * 20 + s.scale(13) / 13 * 19;
  return cover + AppSpacing.sm + text + AppSpacing.xs;
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({
    required this.albums,
    required this.prefs,
    this.empty = const <String>[],
  });
  final List<Album> albums;
  final AlbumPrefs prefs;

  /// Empty albums, shown first.
  final List<String> empty;

  @override
  Widget build(BuildContext context) {
    final int columns = _albumColumns(context);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.lg,
          mainAxisExtent: _albumTileExtent(context, columns),
        ),
        itemCount: empty.length + albums.length,
        itemBuilder: (BuildContext context, int i) {
          if (i < empty.length) return _EmptyAlbumTile(name: empty[i]);
          final Album a = albums[i - empty.length];
          return _AlbumTile(
            album: a,
            pinned: prefs.pinned.contains(a.id),
            coverId: prefs.covers[a.id],
          );
        },
      ),
    );
  }
}

class _AlbumTile extends ConsumerWidget {
  const _AlbumTile({
    required this.album,
    required this.pinned,
    required this.coverId,
  });

  final Album album;
  final bool pinned;
  final String? coverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    // A picked cover that has since been deleted falls back to the newest item.
    final AssetEntity? cover = coverId == null
        ? album.cover
        : (ref.watch(assetByIdProvider(coverId!)).value ?? album.cover);
    // The cover lifts out of its square with the album's menu under it.
    Future<void> hold() async {
      // The cover is the square at the top of this tile.
      final RenderBox box = context.findRenderObject()! as RenderBox;
      final Rect square =
          box.localToGlobal(Offset.zero) & Size.square(box.size.width);
      final AlbumOption? choice = await showLiftMenu<AlbumOption>(
        context,
        from: square,
        fromRadius: AppRadii.md,
        aspectRatio: 1,
        preview: ColoredBox(
          color: cs.surfaceContainerHigh,
          child: cover == null
              ? Icon(CupertinoIcons.rectangle_stack, color: cs.onSurfaceVariant)
              : Image(
                  image: AssetEntityImageProvider(
                    cover,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(384),
                  ),
                  fit: BoxFit.cover,
                ),
        ),
        actions: <LiftAction<AlbumOption>>[
          for (final AlbumOption o in AlbumOption.values)
            LiftAction<AlbumOption>(
              o,
              o.labelFor(pinned: pinned),
              o == AlbumOption.pin && pinned
                  ? CupertinoIcons.pin_slash
                  : o.icon,
              destructive: o == AlbumOption.delete,
            ),
        ],
      );
      if (choice == null || !context.mounted) return;
      await runAlbumOption(context, ref, album, choice);
    }

    return Semantics(
      button: true,
      label:
          '${album.name}, ${Fmt.count(album.count, 'item')}'
          '${pinned ? ', pinned' : ''}',
      hint: 'Long-press for options',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => context.push('/albums/folder/${album.id}'),
        onLongPress: hold,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: ColoredBox(
                  color: cs.surfaceContainerHigh,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (cover != null)
                        AnimatedSwitcher(
                          duration: AppMotion.medium,
                          // The default layout centres the child at its own
                          // size, which letterboxed portrait and landscape
                          // covers instead of filling the square.
                          layoutBuilder: (Widget? current, List<Widget> old) =>
                              Stack(
                                fit: StackFit.expand,
                                children: <Widget>[...old, ?current],
                              ),
                          child: Image(
                            key: ValueKey<String>(cover.id),
                            image: AssetEntityImageProvider(
                              cover,
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize.square(384),
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      if (pinned)
                        Positioned(
                          right: AppSpacing.sm,
                          top: AppSpacing.sm,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: cs.surfaceContainerLowest,
                            child: Icon(
                              CupertinoIcons.pin_fill,
                              size: 14,
                              color: cs.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              Fmt.count(album.count, 'item'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAlbumTile extends ConsumerWidget {
  const _EmptyAlbumTile({required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    void open() => context.push(
      Uri(
        path: '/albums/empty',
        queryParameters: <String, String>{'name': name},
      ).toString(),
    );
    return Semantics(
      button: true,
      label: '$name, empty album',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: open,
        onLongPress: () {
          AppHaptics.longPress();
          open();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(
                  CupertinoIcons.rectangle_stack,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'Empty',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumsSkeleton extends StatelessWidget {
  const _AlbumsSkeleton();

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Skeletonizer(
      enabled: true,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          // Where the grid starts under the "On this phone" heading.
          AppSpacing.xl + 24 + AppSpacing.sm,
          AppSpacing.lg,
          0,
        ),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _albumColumns(context),
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.lg,
          mainAxisExtent: _albumTileExtent(context, _albumColumns(context)),
        ),
        itemCount: 9,
        itemBuilder: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Album name',
              maxLines: 1,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text(
              '000 items',
              maxLines: 1,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
