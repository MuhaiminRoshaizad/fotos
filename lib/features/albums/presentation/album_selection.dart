import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/selection/selection.dart';
import '../../../core/widgets/toast.dart';
import '../data/album_prefs.dart';
import '../data/galleries.dart';
import 'album_tiles.dart';
import 'gallery_sheets.dart';

/// Starts selecting on the Albums tab, with [first] already selected when
/// it starts from a tile's menu.
void startAlbumSelection(WidgetRef ref, {String? first}) => ref
    .read(selectionProvider.notifier)
    .start(
      albumsSelectionOwner,
      albumSelectionActions(ref),
      initial: first == null ? const <String>{} : <String>{first},
    );

/// Every album and gallery the Albums tab shows without a search: galleries,
/// and albums not inside one.
Set<String> selectableAlbumIds(WidgetRef ref) {
  final List<Gallery> galleries =
      ref.read(galleriesProvider).value ?? const <Gallery>[];
  final Set<String> grouped = <String>{
    for (final Gallery g in galleries) ...g.albumIds,
  };
  return <String>{
    for (final Gallery g in galleries) g.id,
    for (final Album a in ref.read(albumsProvider).value ?? const <Album>[])
      if (!grouped.contains(a.id)) a.id,
  };
}

/// What the selection bar offers while albums are selected.
List<SelectionAction> albumSelectionActions(WidgetRef ref) {
  void done() => ref.read(selectionProvider.notifier).clear();
  List<Album> albumsIn(Set<String> ids) => <Album>[
    for (final Album a in ref.read(albumsProvider).value ?? const <Album>[])
      if (ids.contains(a.id)) a,
  ];
  return <SelectionAction>[
    SelectionAction(
      icon: CupertinoIcons.rectangle_stack_badge_plus,
      label: 'Add to gallery',
      run: (BuildContext context, Set<String> ids) async {
        final List<Album> albums = albumsIn(ids);
        if (albums.isEmpty) {
          showToast(
            context,
            "A gallery can't go inside a gallery. Pick albums.",
            failed: true,
          );
          return;
        }
        if (await addAlbumsToGallery(context, ref, albums)) done();
      },
    ),
    SelectionAction(
      icon: CupertinoIcons.pin,
      label: 'Pin',
      run: (BuildContext context, Set<String> ids) async {
        final List<String> pinned =
            (ref.read(albumPrefsProvider).value ?? const AlbumPrefs()).pinned;
        // Pins them, or unpins them when every one is pinned already.
        final bool pin = !ids.every(pinned.contains);
        await ref
            .read(albumPrefsProvider.notifier)
            .setPinned(ids.toList(), pinned: pin);
        if (context.mounted) {
          showToast(context, '${pin ? 'Pinned' : 'Unpinned'} ${ids.length}');
        }
        done();
      },
    ),
    SelectionAction(
      icon: CupertinoIcons.rectangle_stack_badge_minus,
      label: 'Remove from gallery',
      run: (BuildContext context, Set<String> ids) async {
        final List<Gallery> galleries =
            ref.read(galleriesProvider).value ?? const <Gallery>[];
        final List<Album> inGalleries = <Album>[
          for (final Album a in albumsIn(ids))
            if (galleryOf(galleries, a.id) != null) a,
        ];
        if (inGalleries.isEmpty) {
          showToast(context, 'None of these is in a gallery.', failed: true);
          return;
        }
        for (final Album a in inGalleries) {
          await ref.read(galleriesProvider.notifier).remove(a.id);
        }
        if (context.mounted) {
          showToast(
            context,
            'Took ${Fmt.count(inGalleries.length, 'album')} out of '
            '${inGalleries.length == 1 ? 'its gallery' : 'their galleries'}',
          );
        }
        done();
      },
    ),
  ];
}
