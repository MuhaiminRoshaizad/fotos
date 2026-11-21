import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
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
import '../../files/data/files_repository.dart';
import '../../files/domain/file_entry.dart';
import '../../files/presentation/files_providers.dart';
import '../data/album_prefs.dart';
import '../data/galleries.dart';
import 'albums_providers.dart';
import 'follow_albums.dart';
import 'gallery_sheets.dart';

/// What can be done to an album from its menu.
enum AlbumOption {
  pin('Pin to top', CupertinoIcons.pin),
  rename('Rename', CupertinoIcons.pencil),
  gallery('Add to gallery', CupertinoIcons.rectangle_stack_badge_plus),
  cover('Change cover', CupertinoIcons.photo),
  sort('Sort', CupertinoIcons.arrow_up_arrow_down),
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

  final MediaRepository repo = ref.read(mediaRepositoryProvider);
  final String? from = await repo.folderOf(album);
  if (from == null || !context.mounted) return null;
  if (name.toLowerCase() == album.name.toLowerCase()) {
    return _renameCaseOnly(context, ref, album, from, name);
  }
  // Opened from its tile on the Albums tab, the album's new id takes that
  // tile away mid-rename, and its ref and context with it. The steps after
  // the move use these instead, or the pin is lost and nothing is said.
  final ProviderContainer providers = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  void say(String message, {bool failed = false}) =>
      showToast(context, message, failed: failed, overlay: overlay);

  final String target = renamedFolder(from, name);
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
  providers.invalidate(libraryProvider);
  providers.invalidate(albumsProvider);
  if (failed > 0) {
    say("Couldn't rename ${album.name}.", failed: true);
    return null;
  }
  final List<Album> after = await providers.read(albumsProvider.future);
  Album? renamed;
  for (final Album a in after) {
    if (a.name == name && await repo.folderOf(a) == target) {
      renamed = a;
      break;
    }
  }
  if (renamed == null) {
    // Nothing reached a folder of the new name; say so rather than claim
    // a rename that didn't happen.
    say("Couldn't rename ${album.name}.", failed: true);
    return null;
  }
  await followAlbums(providers, <String, String>{album.id: renamed.id});
  await providers
      .read(readModesProvider.notifier)
      .follow(readingKey(from), readingKey(target));
  // Android leaves the old folder behind, empty. A delete that isn't empty
  // fails and keeps it, as when other files or subfolders are still there.
  try {
    final String root = await providers.read(storageRootProvider.future);
    await Directory(p.join(root, from)).delete();
  } on FileSystemException {
    // Something else is in it, or there is no All files access to clear it.
  }
  say('Renamed to $name');
  return renamed;
}

/// Changes only the capital letters of [album]'s name. Moving its items
/// can't do that: shared storage ignores letter case, so they land back in
/// the folder they came from. The folder itself is renamed instead, which
/// needs All files access. The album keeps its id, since Android derives it
/// from the folder's path in lower case.
Future<Album?> _renameCaseOnly(
  BuildContext context,
  WidgetRef ref,
  Album album,
  String relativePath,
  String name,
) async {
  if (!await ref.read(nativeChannelProvider).hasAllFilesAccess()) {
    if (context.mounted) {
      showToast(
        context,
        'Changing only capital letters needs All files access. Open Files '
        'once to allow it.',
        failed: true,
      );
    }
    return null;
  }
  final String root = await ref.read(storageRootProvider.future);
  final FilesRepository files = ref.read(filesRepositoryProvider);
  final FileEntry? folder = files.entryAtSync(p.join(root, relativePath));
  bool ok = folder != null;
  if (folder != null) {
    try {
      await files.rename(folder, name);
    } on FileSystemException {
      ok = false;
    }
  }
  if (ok) {
    await ref
        .read(readModesProvider.notifier)
        .follow(
          readingKey(relativePath),
          readingKey(renamedFolder(relativePath, name)),
        );
  }
  ref.invalidate(libraryProvider);
  ref.invalidate(albumsProvider);
  Album? renamed;
  for (final Album a in await ref.read(albumsProvider.future)) {
    if (a.id == album.id && a.name == name) renamed = a;
  }
  if (context.mounted) {
    renamed != null && ok
        ? showToast(context, 'Renamed to $name')
        : showToast(context, 'Couldn\'t rename ${album.name}.', failed: true);
  }
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
    builder: (BuildContext ctx) => DraggableSheet(
      initialSize: 0.7,
      maxSize: 0.95,
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
    option: SortOption(
      'Favourites first',
      footer: 'Favourites sit at the top, like a pinned album.',
      value: current.favouritesFirst,
    ),
    forAllLabel: 'Use for all albums',
  );
  if (next == null) return;
  final AlbumSort sort = AlbumSort(
    AlbumSortBy.values[next.by],
    reversed: next.reversed,
    favouritesFirst: next.option,
  );
  final AlbumPrefsNotifier prefs = ref.read(albumPrefsProvider.notifier);
  await (next.forAll
      ? prefs.setSortForAll(album.id, sort)
      : prefs.setSort(album.id, sort));
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
Future<bool> deleteAlbum(BuildContext context, WidgetRef ref, Album album) =>
    deleteAlbums(context, ref, <Album>[album]);

/// Moves every item in [albums] to Recently deleted in one request, after
/// asking. [galleriesKept] says so when galleries were selected too, since
/// those are left alone. Returns whether anything was deleted.
Future<bool> deleteAlbums(
  BuildContext context,
  WidgetRef ref,
  List<Album> albums, {
  bool galleriesKept = false,
}) async {
  if (albums.isEmpty) return false;
  final int count = albums.fold(0, (int n, Album a) => n + a.count);
  final bool one = count == 1;
  final bool ok = await confirmAction(
    context,
    title: albums.length == 1
        ? 'Delete ${albums.single.name}?'
        : 'Delete ${Fmt.count(albums.length, 'album')}?',
    message:
        '${albums.length == 1 ? 'Its' : 'Their'} ${Fmt.count(count, 'item')} '
        '${one ? 'moves' : 'move'} to Recently deleted. You can restore '
        '${one ? 'it' : 'them'} for 30 days.'
        '${galleriesKept ? ' Selected galleries are not deleted.' : ''}',
    confirmLabel: 'Delete',
  );
  if (!ok || !context.mounted) return false;
  final MediaRepository repo = ref.read(mediaRepositoryProvider);
  final List<AssetEntity> all = <AssetEntity>[
    for (final Album a in albums) ...await repo.albumItems(a),
  ];
  if (!context.mounted) return false;
  final Set<String> gone = await ref
      .read(mediaActionsProvider)
      .trash(context, all, confirm: false);
  ref.invalidate(albumsProvider);
  return gone.isNotEmpty;
}
