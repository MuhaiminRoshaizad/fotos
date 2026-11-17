import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/add_to_album.dart' show AlbumThumb;
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/toast.dart';
import '../data/album_prefs.dart';
import '../data/galleries.dart';
import 'album_sheets.dart';
import 'album_tiles.dart';
import 'new_album.dart';

/// What can be done to a gallery from its menu.
enum GalleryOption {
  pin('Pin to top', CupertinoIcons.pin),
  add('Add albums', CupertinoIcons.rectangle_stack_badge_plus),
  rename('Rename', CupertinoIcons.pencil),
  sort('Sort', CupertinoIcons.arrow_up_arrow_down),
  ungroup('Ungroup', CupertinoIcons.rectangle_stack_badge_minus);

  const GalleryOption(this.label, this.icon);

  final String label;
  final IconData icon;

  String labelFor({required bool pinned}) =>
      this == GalleryOption.pin && pinned ? 'Unpin' : label;

  IconData iconFor({required bool pinned}) =>
      this == GalleryOption.pin && pinned ? CupertinoIcons.pin_slash : icon;
}

/// The ＋ on the Albums tab: a new album, or a new gallery to hold albums.
Future<void> showNewMenu(BuildContext context, WidgetRef ref) async {
  final String? choice = await showActionSheet<String>(
    context,
    choices: const <SheetChoice<String>>[
      SheetChoice<String>('album', 'New album'),
      SheetChoice<String>('gallery', 'New gallery'),
    ],
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'album') {
    await createAlbum(context, ref);
  } else {
    await createGallery(context, ref);
  }
}

/// The gallery's menu as an action sheet, for the button on its page.
/// Returns true when the gallery was ungrouped.
Future<bool> showGalleryOptions(
  BuildContext context,
  WidgetRef ref,
  Gallery gallery,
) async {
  final bool pinned = (ref.read(albumPrefsProvider).value ?? const AlbumPrefs())
      .pinned
      .contains(gallery.id);
  final GalleryOption? choice = await showActionSheet<GalleryOption>(
    context,
    title: gallery.name,
    choices: <SheetChoice<GalleryOption>>[
      for (final GalleryOption o in GalleryOption.values)
        if (o != GalleryOption.add)
          SheetChoice<GalleryOption>(o, o.labelFor(pinned: pinned)),
    ],
  );
  if (choice == null || !context.mounted) return false;
  return runGalleryOption(context, ref, gallery, choice);
}

/// Runs [option] on [gallery]. Returns true when it was ungrouped.
Future<bool> runGalleryOption(
  BuildContext context,
  WidgetRef ref,
  Gallery gallery,
  GalleryOption option,
) async {
  final AlbumPrefs prefs =
      ref.read(albumPrefsProvider).value ?? const AlbumPrefs();
  final bool pinned = prefs.pinned.contains(gallery.id);
  switch (option) {
    case GalleryOption.pin:
      await ref.read(albumPrefsProvider.notifier).togglePin(gallery.id);
      if (context.mounted) {
        showToast(
          context,
          pinned ? 'Unpinned ${gallery.name}' : 'Pinned ${gallery.name}',
        );
      }
    case GalleryOption.add:
      await addAlbumsTo(context, ref, gallery);
    case GalleryOption.rename:
      final List<Gallery> all = await ref.read(galleriesProvider.future);
      if (!context.mounted) return false;
      final String? name = await promptName(
        context,
        title: 'Rename gallery',
        label: 'Gallery name',
        hint: 'e.g. Clips',
        confirmLabel: 'Rename',
        initial: gallery.name,
        validate: (String v) => validateFolderName(v, <String>[
          for (final Gallery g in all)
            if (g.id != gallery.id) g.name,
        ]),
      );
      if (name == null || name == gallery.name) return false;
      await ref.read(galleriesProvider.notifier).rename(gallery.id, name);
      if (context.mounted) showToast(context, 'Renamed to $name');
    case GalleryOption.sort:
      await showGalleryOrderSheet(context, ref, gallery);
    case GalleryOption.ungroup:
      final bool ok = await confirmAction(
        context,
        title: 'Ungroup ${gallery.name}?',
        message:
            'Its albums go back to Albums. No photos or videos are moved '
            'or deleted.',
        confirmLabel: 'Ungroup',
      );
      if (!ok) return false;
      if (pinned) {
        await ref.read(albumPrefsProvider.notifier).togglePin(gallery.id);
      }
      await ref.read(galleriesProvider.notifier).delete(gallery.id);
      if (context.mounted) showToast(context, 'Ungrouped ${gallery.name}');
      return true;
  }
  return false;
}

/// Names a new gallery, then picks the albums to put in it, then opens it.
Future<void> createGallery(BuildContext context, WidgetRef ref) async {
  final List<Gallery> galleries = await ref.read(galleriesProvider.future);
  if (!context.mounted) return;
  final String? name = await promptName(
    context,
    title: 'New gallery',
    label: 'Gallery name',
    hint: 'e.g. Clips',
    confirmLabel: 'Next',
    validate: (String v) => validateFolderName(v, <String>[
      for (final Gallery g in galleries) g.name,
    ]),
  );
  if (name == null || !context.mounted) return;
  final List<Album> albums = await ref.read(albumsProvider.future);
  if (!context.mounted) return;
  final List<String>? picked = await _pickAlbums(
    context,
    title: 'Choose albums for $name',
    albums: albums,
    galleries: galleries,
    confirmLabel: 'Make gallery',
    allowNone: true,
  );
  if (picked == null || !context.mounted) return;
  final String id = await ref
      .read(galleriesProvider.notifier)
      .create(name, picked);
  if (!context.mounted) return;
  showToast(context, 'Made gallery $name');
  context.push(galleryLocation(id));
}

/// Picks albums not yet in [gallery] and puts them in it.
Future<void> addAlbumsTo(
  BuildContext context,
  WidgetRef ref,
  Gallery gallery,
) async {
  final List<Album> albums = await ref.read(albumsProvider.future);
  final List<Gallery> galleries = await ref.read(galleriesProvider.future);
  if (!context.mounted) return;
  final List<String>? picked = await _pickAlbums(
    context,
    title: 'Add to ${gallery.name}',
    albums: <Album>[
      for (final Album a in albums)
        if (!gallery.albumIds.contains(a.id)) a,
    ],
    galleries: galleries,
    confirmLabel: 'Add',
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await ref.read(galleriesProvider.notifier).add(gallery.id, picked);
  if (context.mounted) {
    showToast(
      context,
      'Added ${Fmt.count(picked.length, 'album')} to ${gallery.name}',
    );
  }
}

/// From an album's menu: puts [album] in a gallery, or a new one.
Future<bool> addAlbumToGallery(
  BuildContext context,
  WidgetRef ref,
  Album album,
) => addAlbumsToGallery(context, ref, <Album>[album]);

/// Puts [albums] in a gallery the user picks, or a new one, taking them out
/// of any gallery they were in. Returns whether they were added.
Future<bool> addAlbumsToGallery(
  BuildContext context,
  WidgetRef ref,
  List<Album> albums,
) async {
  final List<Gallery> galleries = await ref.read(galleriesProvider.future);
  if (!context.mounted || albums.isEmpty) return false;
  final String what = albums.length == 1
      ? albums.single.name
      : Fmt.count(albums.length, 'album');
  final String? choice = await showActionSheet<String>(
    context,
    title: 'Add $what to',
    choices: <SheetChoice<String>>[
      for (final Gallery g in galleries) SheetChoice<String>(g.id, g.name),
      const SheetChoice<String>('', 'New gallery'),
    ],
  );
  if (choice == null || !context.mounted) return false;
  final GalleriesNotifier notifier = ref.read(galleriesProvider.notifier);
  final List<String> ids = <String>[for (final Album a in albums) a.id];
  String name;
  if (choice.isEmpty) {
    final String? n = await promptName(
      context,
      title: 'New gallery',
      label: 'Gallery name',
      hint: 'e.g. Clips',
      confirmLabel: 'Make gallery',
      validate: (String v) => validateFolderName(v, <String>[
        for (final Gallery g in galleries) g.name,
      ]),
    );
    if (n == null) return false;
    await notifier.create(n, ids);
    name = n;
  } else {
    await notifier.add(choice, ids);
    name = galleries.firstWhere((Gallery g) => g.id == choice).name;
  }
  if (context.mounted) showToast(context, 'Added $what to $name');
  return true;
}

/// Chooses albums from [albums]. Returns their ids in the order shown, or
/// null when the sheet is dismissed.
Future<List<String>?> _pickAlbums(
  BuildContext context, {
  required String title,
  required List<Album> albums,
  required List<Gallery> galleries,
  required String confirmLabel,
  bool allowNone = false,
}) => showAppSheet<List<String>>(
  context,
  scrollControlled: true,
  builder: (BuildContext ctx) => _AlbumPicker(
    title: title,
    albums: albums,
    galleries: galleries,
    confirmLabel: confirmLabel,
    allowNone: allowNone,
  ),
);

class _AlbumPicker extends StatefulWidget {
  const _AlbumPicker({
    required this.title,
    required this.albums,
    required this.galleries,
    required this.confirmLabel,
    required this.allowNone,
  });

  final String title;
  final List<Album> albums;
  final List<Gallery> galleries;
  final String confirmLabel;
  final bool allowNone;

  @override
  State<_AlbumPicker> createState() => _AlbumPickerState();
}

class _AlbumPickerState extends State<_AlbumPicker> {
  final Set<String> _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool can = widget.allowNone || _picked.isNotEmpty;
    return DraggableSheet(
      initialSize: 0.7,
      maxSize: 0.92,
      builder: (BuildContext context, ScrollController scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetTitle(
            widget.title,
            subtitle: _picked.isEmpty
                ? 'Tap albums to choose them'
                : '${Fmt.count(_picked.length, 'album')} chosen',
          ),
          Expanded(
            child: widget.albums.isEmpty
                ? Center(
                    child: Text(
                      'Every album is already in this gallery.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    controller: scroll,
                    children: <Widget>[
                      InsetGroup(
                        dividerIndent: 14 + AlbumThumb.size + AppSpacing.md,
                        children: <Widget>[
                          for (final Album a in widget.albums)
                            _row(context, cs, a),
                        ],
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FilledButton(
              onPressed: can
                  ? () => Navigator.of(context).pop(<String>[
                      for (final Album a in widget.albums)
                        if (_picked.contains(a.id)) a.id,
                    ])
                  : null,
              child: Text(
                _picked.isEmpty
                    ? widget.confirmLabel
                    : '${widget.confirmLabel} (${_picked.length})',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ColorScheme cs, Album a) {
    final bool on = _picked.contains(a.id);
    final Gallery? inside = galleryOf(widget.galleries, a.id);
    return Semantics(
      checked: on,
      child: GroupRow(
        leading: AlbumThumb(
          child: a.cover == null
              ? const Icon(CupertinoIcons.rectangle_stack)
              : Image(
                  image: AssetEntityImageProvider(
                    a.cover!,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(160),
                  ),
                  fit: BoxFit.cover,
                ),
        ),
        leadingWidth: AlbumThumb.size,
        title: a.name,
        // Choosing it moves it out of the gallery it is in now.
        subtitle: inside == null
            ? Fmt.count(a.count, 'item')
            : '${Fmt.count(a.count, 'item')} · in ${inside.name}',
        chevron: false,
        trailing: Icon(
          on ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
          color: on ? cs.primary : cs.onSurfaceVariant,
        ),
        onTap: () =>
            setState(() => on ? _picked.remove(a.id) : _picked.add(a.id)),
      ),
    );
  }
}
