import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/lift_menu.dart';
import '../data/album_prefs.dart';
import '../data/galleries.dart';
import 'album_sheets.dart';
import 'albums_providers.dart';
import 'gallery_sheets.dart';

/// Columns of album tiles at this screen width: two on phones, more on
/// tablets so covers stay a sensible size.
int albumColumns(BuildContext context) {
  final double width = MediaQuery.sizeOf(context).width;
  return width >= 900 ? 5 : (width >= 600 ? 4 : 2);
}

/// Height of one album tile: the square cover plus two lines of text at the
/// user's text size. A fixed aspect ratio overflowed at large text sizes.
double albumTileExtent(BuildContext context, int columns) {
  final double width = MediaQuery.sizeOf(context).width;
  final double cover =
      (width - AppSpacing.lg * 2 - AppSpacing.md * (columns - 1)) / columns;
  final TextScaler s = MediaQuery.textScalerOf(context);
  // Name (14 on a 20 line) and count (13 on a 19 line).
  final double text = s.scale(14) / 14 * 20 + s.scale(13) / 13 * 19;
  return cover + AppSpacing.sm + text + AppSpacing.xs;
}

/// Album and gallery tiles in columns.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final int columns = albumColumns(context);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.lg,
          mainAxisExtent: albumTileExtent(context, columns),
        ),
        itemCount: tiles.length,
        itemBuilder: (BuildContext context, int i) => tiles[i],
      ),
    );
  }
}

/// The album's cover: the one picked for it, or its newest item. A picked
/// cover that has since been deleted falls back to the newest item.
AssetEntity? albumCover(WidgetRef ref, Album album, AlbumPrefs prefs) {
  final String? id = prefs.covers[album.id];
  if (id == null) return album.cover;
  return ref.watch(assetByIdProvider(id)).value ?? album.cover;
}

Widget _coverImage(AssetEntity cover) => Image(
  key: ValueKey<String>(cover.id),
  image: AssetEntityImageProvider(
    cover,
    isOriginal: false,
    thumbnailSize: const ThumbnailSize.square(384),
  ),
  fit: BoxFit.cover,
);

/// The pin in the corner of a pinned tile.
class _PinBadge extends StatelessWidget {
  const _PinBadge();

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Positioned(
      right: AppSpacing.sm,
      top: AppSpacing.sm,
      child: CircleAvatar(
        radius: 12,
        backgroundColor: cs.surfaceContainerLowest,
        child: Icon(CupertinoIcons.pin_fill, size: 14, color: cs.primary),
      ),
    );
  }
}

/// A square picture with a name and a count under it, as every album and
/// gallery tile is laid out.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.picture,
    required this.name,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final Widget picture;
  final String name;
  final String count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      hint: 'Long-press for options',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: ColoredBox(
                  color: cs.surfaceContainerHigh,
                  child: picture,
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
              count,
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

/// The square under [context]'s tile, where a lift menu starts from.
Rect _square(BuildContext context) {
  final RenderBox box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & Size.square(box.size.width);
}

class AlbumTile extends ConsumerWidget {
  const AlbumTile({super.key, required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AlbumPrefs prefs =
        ref.watch(albumPrefsProvider).value ?? const AlbumPrefs();
    final bool pinned = prefs.pinned.contains(album.id);
    final bool inGallery =
        galleryOf(
          ref.watch(galleriesProvider).value ?? const <Gallery>[],
          album.id,
        ) !=
        null;
    final AssetEntity? cover = albumCover(ref, album, prefs);
    // The cover lifts out of its square with the album's menu under it.
    Future<void> hold() async {
      final AlbumOption? choice = await showLiftMenu<AlbumOption>(
        context,
        from: _square(context),
        fromRadius: AppRadii.md,
        aspectRatio: 1,
        preview: ColoredBox(
          color: cs.surfaceContainerHigh,
          child: cover == null
              ? Icon(CupertinoIcons.rectangle_stack, color: cs.onSurfaceVariant)
              : _coverImage(cover),
        ),
        actions: <LiftAction<AlbumOption>>[
          for (final AlbumOption o in albumOptionsFor(album))
            LiftAction<AlbumOption>(
              o,
              o.labelFor(pinned: pinned, inGallery: inGallery),
              o.iconFor(pinned: pinned, inGallery: inGallery),
              destructive: o == AlbumOption.delete,
            ),
        ],
      );
      if (choice == null || !context.mounted) return;
      await runAlbumOption(context, ref, album, choice);
    }

    return _Tile(
      label:
          '${album.name}, ${Fmt.count(album.count, 'item')}'
          '${pinned ? ', pinned' : ''}',
      name: album.name,
      count: Fmt.count(album.count, 'item'),
      onTap: () => context.push('/albums/folder/${album.id}'),
      onLongPress: hold,
      picture: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (cover != null)
            AnimatedSwitcher(
              duration: AppMotion.medium,
              // The default layout centres the child at its own size, which
              // letterboxed portrait and landscape covers instead of filling
              // the square.
              layoutBuilder: (Widget? current, List<Widget> old) => Stack(
                fit: StackFit.expand,
                children: <Widget>[...old, ?current],
              ),
              child: _coverImage(cover),
            ),
          if (pinned) const _PinBadge(),
        ],
      ),
    );
  }
}

class EmptyAlbumTile extends ConsumerWidget {
  const EmptyAlbumTile({super.key, required this.name});
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
    return _Tile(
      label: '$name, empty album',
      name: name,
      count: 'Empty',
      onTap: open,
      onLongPress: () {
        AppHaptics.longPress();
        open();
      },
      picture: Icon(CupertinoIcons.rectangle_stack, color: cs.onSurfaceVariant),
    );
  }
}

/// Up to four of a gallery's albums' covers, two by two.
class GalleryMosaic extends ConsumerWidget {
  const GalleryMosaic({super.key, required this.albums});

  /// The gallery's albums, in its order.
  final List<Album> albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AlbumPrefs prefs =
        ref.watch(albumPrefsProvider).value ?? const AlbumPrefs();
    if (albums.isEmpty) {
      return Icon(
        CupertinoIcons.rectangle_stack_badge_plus,
        color: cs.onSurfaceVariant,
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: <Widget>[
        for (int i = 0; i < 4; i++)
          ColoredBox(
            color: cs.surfaceContainerHighest,
            child: switch (i < albums.length
                ? albumCover(ref, albums[i], prefs)
                : null) {
              final AssetEntity cover => _coverImage(cover),
              null => const SizedBox.shrink(),
            },
          ),
      ],
    );
  }
}

class GalleryTile extends ConsumerWidget {
  const GalleryTile({super.key, required this.gallery, required this.albums});

  final Gallery gallery;

  /// Its albums that are on the phone, in the gallery's order.
  final List<Album> albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool pinned =
        (ref.watch(albumPrefsProvider).value ?? const AlbumPrefs()).pinned
            .contains(gallery.id);
    final String count = Fmt.count(albums.length, 'album');
    Future<void> hold() async {
      final GalleryOption? choice = await showLiftMenu<GalleryOption>(
        context,
        from: _square(context),
        fromRadius: AppRadii.md,
        aspectRatio: 1,
        preview: GalleryMosaic(albums: albums),
        actions: <LiftAction<GalleryOption>>[
          for (final GalleryOption o in GalleryOption.values)
            LiftAction<GalleryOption>(
              o,
              o.labelFor(pinned: pinned),
              o.iconFor(pinned: pinned),
            ),
        ],
      );
      if (choice == null || !context.mounted) return;
      await runGalleryOption(context, ref, gallery, choice);
    }

    return _Tile(
      label: '${gallery.name}, gallery of $count${pinned ? ', pinned' : ''}',
      name: gallery.name,
      count: count,
      onTap: () => context.push(galleryLocation(gallery.id)),
      onLongPress: hold,
      picture: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GalleryMosaic(albums: albums),
          if (pinned) const _PinBadge(),
        ],
      ),
    );
  }
}

/// Where gallery [id]'s page lives.
String galleryLocation(String id) =>
    '/albums/gallery/${Uri.encodeComponent(id)}';

/// A grid of placeholder tiles the size of real ones, while albums load.
class AlbumGridSkeleton extends StatelessWidget {
  const AlbumGridSkeleton({super.key, required this.top});

  /// Space above the first row, where the real grid starts.
  final double top;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int columns = albumColumns(context);
    return Skeletonizer(
      enabled: true,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, top, AppSpacing.lg, 0),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.lg,
          mainAxisExtent: albumTileExtent(context, columns),
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
