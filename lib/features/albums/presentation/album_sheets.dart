import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/media_actions.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';
import '../data/album_prefs.dart';

/// What can be done to an album from its menu.
enum AlbumOption {
  pin('Pin to top', CupertinoIcons.pin),
  cover('Change cover', CupertinoIcons.photo),
  sort('Sort', CupertinoIcons.arrow_up_arrow_down),
  delete('Delete album', CupertinoIcons.trash);

  const AlbumOption(this.label, this.icon);

  final String label;
  final IconData icon;

  /// The label for an album that is [pinned] or not.
  String labelFor({required bool pinned}) =>
      this == AlbumOption.pin && pinned ? 'Unpin' : label;
}

bool albumIsPinned(WidgetRef ref, Album album) =>
    (ref.read(albumPrefsProvider).value ?? const AlbumPrefs()).pinned.contains(
      album.id,
    );

/// The album's menu as an action sheet, for the button inside an album.
Future<void> showAlbumOptions(
  BuildContext context,
  WidgetRef ref,
  Album album,
) async {
  final bool pinned = albumIsPinned(ref, album);
  final AlbumOption? choice = await showActionSheet<AlbumOption>(
    context,
    title: album.name,
    choices: <SheetChoice<AlbumOption>>[
      for (final AlbumOption o in AlbumOption.values)
        SheetChoice<AlbumOption>(
          o,
          o.labelFor(pinned: pinned),
          destructive: o == AlbumOption.delete,
        ),
    ],
  );
  if (choice == null || !context.mounted) return;
  await runAlbumOption(context, ref, album, choice);
}

Future<void> runAlbumOption(
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
    case AlbumOption.cover:
      await pickAlbumCover(context, ref, album);
    case AlbumOption.sort:
      await showSortSheet(context, ref, album);
    case AlbumOption.delete:
      await deleteAlbum(context, ref, album);
  }
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
  final (int, bool)? next = await _pickSort(
    context,
    title: 'Sort',
    labels: <String>[for (final AlbumSortBy b in AlbumSortBy.values) b.label],
    directions: <(String, String)>[
      for (final AlbumSortBy b in AlbumSortBy.values) b.directions,
    ],
    by: current.by.index,
    reversed: current.reversed,
  );
  if (next != null) {
    await ref
        .read(albumPrefsProvider.notifier)
        .setSort(
          album.id,
          AlbumSort(AlbumSortBy.values[next.$1], reversed: next.$2),
        );
  }
}

/// Chooses the order of the albums on the Albums tab.
Future<void> showAlbumsOrderSheet(BuildContext context, WidgetRef ref) async {
  final AlbumsOrder current =
      (ref.read(albumPrefsProvider).value ?? const AlbumPrefs()).order;
  final (int, bool)? next = await _pickSort(
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
          AlbumsOrder(AlbumsOrderBy.values[next.$1], reversed: next.$2),
        );
  }
}

/// The sort sheet: a key to sort by and one of its two directions. Returns
/// the chosen key's index and whether the second direction was picked.
Future<(int, bool)?> _pickSort(
  BuildContext context, {
  required String title,
  required List<String> labels,
  required List<(String, String)> directions,
  required int by,
  required bool reversed,
}) => showAppSheet<(int, bool)>(
  context,
  builder: (BuildContext ctx) => _SortSheet(
    title: title,
    labels: labels,
    directions: directions,
    by: by,
    reversed: reversed,
  ),
);

class _SortSheet extends StatefulWidget {
  const _SortSheet({
    required this.title,
    required this.labels,
    required this.directions,
    required this.by,
    required this.reversed,
  });
  final String title;
  final List<String> labels;
  final List<(String, String)> directions;
  final int by;
  final bool reversed;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late int _by = widget.by;
  late bool _reversed = widget.reversed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final (String first, String second) = widget.directions[_by];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetTitle(widget.title),
        // iOS marks the choice with a checkmark, not a radio button.
        InsetGroup(
          children: <Widget>[
            for (final (int i, String label) in widget.labels.indexed)
              Semantics(
                selected: i == _by,
                inMutuallyExclusiveGroup: true,
                child: GroupRow(
                  title: label,
                  chevron: false,
                  trailing: i == _by
                      ? Icon(
                          CupertinoIcons.checkmark,
                          size: 20,
                          color: cs.primary,
                        )
                      : null,
                  onTap: () => setState(() {
                    _by = i;
                    _reversed = false;
                  }),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: CupertinoSlidingSegmentedControl<bool>(
            groupValue: _reversed,
            children: <bool, Widget>{
              false: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(first),
              ),
              true: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(second),
              ),
            },
            onValueChanged: (bool? v) {
              if (v != null) setState(() => _reversed = v);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop((_by, _reversed)),
            child: const Text('Apply'),
          ),
        ),
      ],
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
