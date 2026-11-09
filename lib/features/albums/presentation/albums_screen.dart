import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/media_access_gate.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/album_prefs.dart';
import 'album_sheets.dart';
import 'albums_providers.dart';
import 'new_album.dart';

/// The Albums tab: pinned albums first, then every folder holding media, then
/// Favourites and Recently deleted.
class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Albums',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'New album',
                      onPressed: () => createAlbum(context, ref),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ),
            const Expanded(child: MediaAccessGate(child: _AlbumsBody())),
          ],
        ),
      ),
    );
  }
}

class _AlbumsBody extends ConsumerWidget {
  const _AlbumsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Album>> albums = ref.watch(albumsProvider);
    final AlbumPrefs prefs =
        ref.watch(albumPrefsProvider).value ?? const AlbumPrefs();
    final double bottom = AppNavMetrics.clearance(
      MediaQuery.paddingOf(context).bottom,
    );
    return albums.when(
      skipLoadingOnRefresh: true,
      loading: () => const _AlbumsSkeleton(),
      error: (_, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Couldn\'t load your albums',
        message: 'Something went wrong reading the photo library.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(albumsProvider),
      ),
      data: (List<Album> list) {
        final List<Album> pinned = <Album>[
          for (final String id in prefs.pinned)
            ...list.where((Album a) => a.id == id),
        ];
        final List<Album> rest = list
            .where((Album a) => !prefs.pinned.contains(a.id))
            .toList();
        return CustomScrollView(
          slivers: <Widget>[
            if (pinned.isNotEmpty) ...<Widget>[
              const _Section(title: 'Pinned', icon: Icons.push_pin_outlined),
              _AlbumGrid(albums: pinned, prefs: prefs),
            ],
            const _Section(title: 'On this phone'),
            if (list.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text('No folders with photos or videos yet.'),
                ),
              )
            else
              _AlbumGrid(albums: rest, prefs: prefs),
            const _Section(title: 'More'),
            SliverList.list(
              children: <Widget>[
                _MoreRow(
                  icon: Icons.favorite_border,
                  label: 'Favourites',
                  count: ref.watch(favouritesProvider).value?.length,
                  onTap: () => context.push('/albums/favourites'),
                ),
                _MoreRow(
                  icon: Icons.delete_outline,
                  label: 'Recently deleted',
                  count: ref.watch(trashProvider).value?.length,
                  onTap: () => context.push('/albums/trash'),
                ),
                _MoreRow(
                  icon: Icons.download_for_offline_outlined,
                  label: 'Import from Google Takeout',
                  onTap: () => context.push('/albums/takeout'),
                ),
              ],
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.icon});
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: AppIconSize.badge,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({required this.albums, required this.prefs});
  final List<Album> albums;
  final AlbumPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    // Three across on phones, more on tablets so covers stay a sensible size.
    final int columns = width >= 900 ? 6 : (width >= 600 ? 4 : 3);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.lg,
          childAspectRatio: 0.74,
        ),
        itemCount: albums.length,
        itemBuilder: (BuildContext context, int i) => _AlbumTile(
          album: albums[i],
          pinned: prefs.pinned.contains(albums[i].id),
          coverId: prefs.covers[albums[i].id],
        ),
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
        onLongPress: () {
          AppHaptics.longPress();
          showAlbumOptions(context, ref, album);
        },
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
                          right: 6,
                          top: 6,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: cs.surfaceContainerLowest,
                            child: Icon(
                              Icons.push_pin,
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
            const SizedBox(height: 6),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${album.count}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (count != null)
            Text('$count', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
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
          AppSpacing.xxl + AppSpacing.lg,
          AppSpacing.lg,
          0,
        ),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.lg,
          childAspectRatio: 0.74,
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
            const SizedBox(height: 6),
            const Text('Album name'),
            const Text('000'),
          ],
        ),
      ),
    );
  }
}
