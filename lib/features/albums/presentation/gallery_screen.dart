import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../data/galleries.dart';
import 'album_selection.dart';
import 'album_tiles.dart';
import 'gallery_sheets.dart';
import '../../../core/widgets/bottom_bar_space.dart';

/// A gallery's albums, in the gallery's own order.
class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key, required this.galleryId});

  final String galleryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Gallery? gallery;
    for (final Gallery g
        in ref.watch(galleriesProvider).value ?? const <Gallery>[]) {
      if (g.id == galleryId) gallery = g;
    }
    final Gallery? g = gallery;
    final AsyncValue<List<Album>> albums = ref.watch(albumsProvider);
    final double bottom = bottomClearance(context);
    return LargeTitleScaffold(
      title: g?.name ?? '',
      trailing: g == null
          ? const <Widget>[]
          : <Widget>[
              BarButton.icon(
                icon: CupertinoIcons.plus,
                tooltip: 'Add albums',
                onPressed: () => addAlbumsTo(context, ref, g),
              ),
              BarButton.icon(
                icon: CupertinoIcons.ellipsis,
                tooltip: 'Gallery options',
                onPressed: () async {
                  if (await showGalleryOptions(context, ref, g) &&
                      context.mounted) {
                    context.pop();
                  }
                },
              ),
            ],
      body: (BuildContext context, Widget header) {
        Widget headed(Widget state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            Expanded(child: state),
          ],
        );
        if (g == null) {
          return headed(
            ref.watch(galleriesProvider).isLoading
                ? const AlbumGridSkeleton(top: AppSpacing.sm)
                : const EmptyState(
                    icon: CupertinoIcons.rectangle_stack,
                    title: 'This gallery is gone',
                    message:
                        'It was ungrouped. Its albums are on the Albums '
                        'tab.',
                  ),
          );
        }
        return albums.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => headed(const AlbumGridSkeleton(top: AppSpacing.sm)),
          error: (_, _) => headed(
            EmptyState(
              icon: CupertinoIcons.exclamationmark_circle,
              title: 'Couldn\'t load this gallery',
              message: 'Something went wrong reading the photo library.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(albumsProvider),
            ),
          ),
          data: (List<Album> all) {
            final List<Album> inside = g.order.apply(<Album>[
              for (final Album a in all)
                if (g.albumIds.contains(a.id)) a,
            ]);
            if (inside.isEmpty) {
              return headed(
                EmptyState(
                  icon: CupertinoIcons.rectangle_stack_badge_plus,
                  title: 'No albums in ${g.name} yet',
                  message:
                      'Add albums to keep them together here. Their '
                      'photos stay where they are.',
                  actionLabel: 'Add albums',
                  onAction: () => addAlbumsTo(context, ref, g),
                ),
              );
            }
            final int columns = albumColumns(context);
            return EntranceScope(
              child: CustomScrollView(
                slivers: <Widget>[
                  SliverToBoxAdapter(child: header),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.sm),
                  ),
                  AlbumGrid(
                    tiles: <Widget>[
                      for (final (int i, Album a) in inside.indexed)
                        SlideUpIn(
                          index: i ~/ columns,
                          child: AlbumTile(
                            key: ValueKey<String>(a.id),
                            album: a,
                            onSelect: () =>
                                startAlbumSelection(ref, first: a.id),
                          ),
                        ),
                    ],
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: bottom)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
