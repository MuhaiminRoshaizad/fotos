import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/media_actions.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/media/read_mode.dart';
import '../../../core/media/empty_albums.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/batch_progress.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/sort_sheet.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';
import '../data/album_prefs.dart';
import '../data/galleries.dart';
import 'albums_providers.dart';
import 'gallery_sheets.dart';

/// What can be done to an album from its menu.
enum AlbumOption {
  pin('Pin to top', CupertinoIcons.pin),
  rename('Rename', CupertinoIcons.pencil),
  gallery('Add to gallery', CupertinoIcons.rectangle_stack_badge_plus),
  cover('Change cover', CupertinoIcons.photo),
  sort('Sort', CupertinoIcons.arrow_up_arrow_down),
  reading('Read as', CupertinoIcons.book),
  delete('Delete album', CupertinoIcons.trash);

  const AlbumOption(this.label, this.icon);

  final String label;
  final IconData icon;

  /// The label for an album that is [pinned] or [inGallery], or not.
  String labelFor({required bool pinned, bool inGallery = false}) =>
      switch (this) {
        AlbumOption.pin when pinned => 'Unpin',
        AlbumOption.gallery when inGallery => 'Remove from gallery',
        _ => label,
      };

  IconData iconFor({required bool pinned, bool inGallery = false}) =>
      switch (this) {
        AlbumOption.pin when pinned => CupertinoIcons.pin_slash,
        AlbumOption.gallery when inGallery =>
          CupertinoIcons.rectangle_stack_badge_minus,
        _ => icon,
      };
}

/// Camera and Screenshots keep their folder names: the camera app and
/// Android's screenshot tool write to those folders by name.
bool albumCanBeRenamed(Album album) =>
    !<String>{'camera', 'screenshots'}.contains(album.name.toLowerCase());

/// The options [album]'s menu offers.
List<AlbumOption> albumOptionsFor(Album album) => <AlbumOption>[
  for (final AlbumOption o in AlbumOption.values)
    if (o != AlbumOption.rename || albumCanBeRenamed(album)) o,
];

bool albumIsPinned(WidgetRef ref, Album album) =>
    (ref.read(albumPrefsProvider).value ?? const AlbumPrefs()).pinned.contains(
      album.id,
    );

/// The album's menu as an action sheet, for the button inside an album.
/// Returns the album under its new name when it was renamed, since that
/// gives it a new id.
Future<Album?> showAlbumOptions(
  BuildContext context,
  WidgetRef ref,
  Album album,
) async {
  final bool pinned = albumIsPinned(ref, album);
  final bool inGallery =
      galleryOf(
        ref.read(galleriesProvider).value ?? const <Gallery>[],
        album.id,
      ) !=
      null;
  final AlbumOption? choice = await showActionSheet<AlbumOption>(
    context,
    title: album.name,
    choices: <SheetChoice<AlbumOption>>[
      for (final AlbumOption o in albumOptionsFor(album))
        SheetChoice<AlbumOption>(
          o,
          o.labelFor(pinned: pinned, inGallery: inGallery),
          destructive: o == AlbumOption.delete,
        ),
    ],
  );
  if (choice == null || !context.mounted) return null;
  return runAlbumOption(context, ref, album, choice);
}

/// Runs [option] on [album]. Returns the renamed album after a rename.
Future<Album?> runAlbumOption(
  BuildContext context,
  WidgetRef ref,
  Album album,
  AlbumOption option,
) async {
  switch (option) {
    case AlbumOption.pin:
      final bool pinned = albumIsPinned(ref, album);
      await ref.read(albumPrefsProvider.notifier).togglePin(album.id);
      if (context.mounted) {
        showToast(
          context,
          pinned ? 'Unpinned ${album.name}' : 'Pinned ${album.name}',
        );
      }
    case AlbumOption.rename:
      return renameAlbum(context, ref, album);
    case AlbumOption.gallery:
      final Gallery? inside = galleryOf(
        await ref.read(galleriesProvider.future),
        album.id,
      );
      if (!context.mounted) return null;
      if (inside == null) {
        await addAlbumToGallery(context, ref, album);
      } else {
        await ref.read(galleriesProvider.notifier).remove(album.id);
        if (context.mounted) {
          showToast(context, 'Removed ${album.name} from ${inside.name}');
        }
      }
    case AlbumOption.cover:
      await pickAlbumCover(context, ref, album);
    case AlbumOption.sort:
      await showSortSheet(context, ref, album);
    case AlbumOption.reading:
      await showReadAsSheet(context, ref, album);
    case AlbumOption.delete:
      await deleteAlbum(context, ref, album);
  }
  return null;
}

/// Renames [album] by moving its items into a folder of the new name beside
/// the old one, so other apps see the new name too. Its pin, cover and sort
/// follow it to the new folder's id. Returns the album under its new name.
Future<Album?> renameAlbum(
  BuildContext context,
  WidgetRef ref,
  Album album,
) async {
  final List<Album> albums = await ref.read(albumsProvider.future);
  if (!context.mounted) return null;
  final String? name = await promptName(
    context,
    title: 'Rename album',
    label: 'Album name',
    hint: 'e.g. Holiday 2026',
    confirmLabel: 'Rename',
    initial: album.name,
    validate: (String v) => validateFolderName(v, <String>[
      for (final Album a in albums)
        if (a.id != album.id) a.name,
    ]),
  );
  if (name == null || name == album.name || !context.mounted) return null;

  final String? from = await album.path.relativePathAsync;
  if (from == null || !context.mounted) return null;
  final String target = renamedFolder(from, name);
  final MediaRepository repo = ref.read(mediaRepositoryProvider);
  final List<AssetEntity> items = await repo.albumItems(album);
  if (!context.mounted) return null;
  // Android moves the whole set in one request, so the bar runs until it
  // answers.
  final int failed = await runBatch<List<AssetEntity>>(
    context,
    verb: 'Renaming',
    doneVerb: 'Renamed',
    what: album.name,
    items: <List<AssetEntity>>[items],
    each: (List<AssetEntity> all) async {
      if (!await repo.moveTo(all, target)) throw Exception('not moved');
    },
  );
  ref.invalidate(libraryProvider);
  ref.invalidate(albumsProvider);
  if (failed > 0) {
    if (context.mounted) {
      showToast(context, 'Couldn\'t rename ${album.name}.', failed: true);
    }
    return null;
  }
  final List<Album> after = await ref.read(albumsProvider.future);
  Album? renamed;
  for (final Album a in after) {
    if (a.name == name && await a.path.relativePathAsync == target) {
      renamed = a;
      break;
    }
  }
  if (renamed != null) {
    await ref.read(albumPrefsProvider.notifier).rekey(album.id, renamed.id);
    await ref.read(galleriesProvider.notifier).rekey(album.id, renamed.id);
    // Home screen widgets set to this album follow it too.
    await ref
        .read(nativeChannelProvider)
        .rekeyWidgetAlbum(album.id, renamed.id);
  }
  if (context.mounted) showToast(context, 'Renamed to $name');
  return renamed;
}

Future<void> pickAlbumCover(
  BuildContext context,
  WidgetRef ref,
  Album album,
) async {
  final List<AssetEntity> items = await ref
      .read(mediaRepositoryProvider)
      .albumItems(album);
  if (!context.mounted) return;
  final String? id = await showAppSheet<String>(
    context,
    scrollControlled: true,
    builder: (BuildContext ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (BuildContext ctx, ScrollController scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetTitle('Choose a cover'),
          Expanded(
            child: GridView.builder(
              controller: scroll,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: items.length,
              itemBuilder: (BuildContext ctx, int i) => Semantics(
                button: true,
                label: 'Use photo from ${Fmt.date(items[i].createDateTime)}',
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(items[i].id),
                  child: Image(
                    image: AssetEntityImageProvider(
                      items[i],
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(256),
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  if (id == null) return;
  await ref.read(albumPrefsProvider.notifier).setCover(album.id, id);
  if (context.mounted) showToast(context, 'Cover changed');
}

Future<void> showSortSheet(
  BuildContext context,
  WidgetRef ref,
  Album album,
) async {
  final AlbumSort current =
      (ref.read(albumPrefsProvider).value ?? const AlbumPrefs()).sortFor(
        album.id,
      );
  final SortPick? next = await pickSort(
    context,
    title: 'Sort',
    labels: <String>[for (final AlbumSortBy b in AlbumSortBy.values) b.label],
    directions: <(String, String)>[
      for (final AlbumSortBy b in AlbumSortBy.values) b.directions,
    ],
    by: current.by.index,
    reversed: current.reversed,
    forAllLabel: 'Use for all albums',
  );
  if (next == null) return;
  final AlbumSort sort = AlbumSort(
    AlbumSortBy.values[next.by],
    reversed: next.reversed,
  );
  final AlbumPrefsNotifier prefs = ref.read(albumPrefsProvider.notifier);
  await (next.forAll
      ? prefs.setSortForAll(album.id, sort)
      : prefs.setSort(album.id, sort));
}

/// Chooses how [album] is read: as photos, as pages turned by a tap on
/// either edge, or as one long strip.
Future<void> showReadAsSheet(
  BuildContext context,
  WidgetRef ref,
  Album album,
) async {
  final ReadMode now =
      (ref.read(albumPrefsProvider).value ?? const AlbumPrefs()).readingFor(
        album.id,
      );
  final ReadMode? mode = await showActionSheet<ReadMode>(
    context,
    title: 'Read ${album.name} as',
    message: 'Now: ${now.label}',
    choices: const <SheetChoice<ReadMode>>[
      SheetChoice<ReadMode>(ReadMode.photos, 'Photos'),
      SheetChoice<ReadMode>(ReadMode.pages, 'Pages: tap the edges to turn'),
      SheetChoice<ReadMode>(ReadMode.strip, 'Strip: one long scroll'),
    ],
  );
  if (mode == null || mode == now) return;
  await ref.read(albumPrefsProvider.notifier).setReading(album.id, mode);
  if (context.mounted) {
    showToast(context, '${album.name} reads as ${mode.label.toLowerCase()}');
  }
}

/// Chooses the order of the albums on the Albums tab.
Future<void> showAlbumsOrderSheet(BuildContext context, WidgetRef ref) async {
  final AlbumsOrder current =
      (ref.read(albumPrefsProvider).value ?? const AlbumPrefs()).order;
  final SortPick? next = await pickSort(
    context,
    title: 'Sort albums',
    labels: <String>[
      for (final AlbumsOrderBy b in AlbumsOrderBy.values) b.label,
    ],
    directions: <(String, String)>[
      for (final AlbumsOrderBy b in AlbumsOrderBy.values) b.directions,
    ],
    by: current.by.index,
    reversed: current.reversed,
  );
  if (next != null) {
    await ref
        .read(albumPrefsProvider.notifier)
        .setOrder(
          AlbumsOrder(AlbumsOrderBy.values[next.by], reversed: next.reversed),
        );
  }
}

/// Chooses the order of the albums inside [gallery].
Future<void> showGalleryOrderSheet(
  BuildContext context,
  WidgetRef ref,
  Gallery gallery,
) async {
  final SortPick? next = await pickSort(
    context,
    title: 'Sort ${gallery.name}',
    labels: <String>[
      for (final AlbumsOrderBy b in AlbumsOrderBy.values) b.label,
    ],
    directions: <(String, String)>[
      for (final AlbumsOrderBy b in AlbumsOrderBy.values) b.directions,
    ],
    by: gallery.order.by.index,
    reversed: gallery.order.reversed,
  );
  if (next != null) {
    await ref
        .read(galleriesProvider.notifier)
        .setOrder(
          gallery.id,
          AlbumsOrder(AlbumsOrderBy.values[next.by], reversed: next.reversed),
        );
  }
}

/// Moves every item in [album] to Android's trash, which also removes the
/// folder from Albums once it is empty.
Future<bool> deleteAlbum(
  BuildContext context,
  WidgetRef ref,
  Album album,
) async {
  final bool ok = await confirmAction(
    context,
    title: 'Delete ${album.name}?',
    message:
        'Its ${Fmt.count(album.count, 'item')} move to Recently deleted. '
        'You can restore them for 30 days.',
    confirmLabel: 'Delete',
  );
  if (!ok || !context.mounted) return false;
  final List<AssetEntity> items = await ref
      .read(mediaRepositoryProvider)
      .albumItems(album);
  if (!context.mounted) return false;
  final Set<String> gone = await ref
      .read(mediaActionsProvider)
      .trash(context, items, confirm: false);
  ref.invalidate(albumsProvider);
  return gone.isNotEmpty;
}
