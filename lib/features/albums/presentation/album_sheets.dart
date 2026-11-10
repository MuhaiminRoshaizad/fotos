import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';
import '../data/album_prefs.dart';

/// Long-press menu for an album: pin, cover, sort, delete.
Future<void> showAlbumOptions(
  BuildContext context,
  WidgetRef ref,
  Album album,
) async {
  final AlbumPrefs prefs =
      ref.read(albumPrefsProvider).value ?? const AlbumPrefs();
  final bool pinned = prefs.pinned.contains(album.id);
  final String? choice = await showAppSheet<String>(
    context,
    builder: (BuildContext ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(album.name, style: Theme.of(ctx).textTheme.titleLarge),
        ),
        SheetAction(
          icon: pinned ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
          label: pinned ? 'Unpin' : 'Pin to top',
          onTap: () => Navigator.of(ctx).pop('pin'),
        ),
        SheetAction(
          icon: CupertinoIcons.photo,
          label: 'Change cover',
          onTap: () => Navigator.of(ctx).pop('cover'),
        ),
        SheetAction(
          icon: CupertinoIcons.arrow_up_arrow_down,
          label: 'Sort',
          onTap: () => Navigator.of(ctx).pop('sort'),
        ),
        SheetAction(
          icon: CupertinoIcons.trash,
          label: 'Delete album',
          destructive: true,
          onTap: () => Navigator.of(ctx).pop('delete'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'pin':
      await ref.read(albumPrefsProvider.notifier).togglePin(album.id);
      if (context.mounted) {
        showToast(
          context,
          pinned ? 'Unpinned ${album.name}' : 'Pinned ${album.name}',
        );
      }
    case 'cover':
      await pickAlbumCover(context, ref, album);
    case 'sort':
      await showSortSheet(context, ref, album);
    case 'delete':
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Text(
              'Choose a cover',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
          ),
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
  final AlbumSort? next = await showAppSheet<AlbumSort>(
    context,
    builder: (BuildContext ctx) => _SortSheet(current: current),
  );
  if (next != null) {
    await ref.read(albumPrefsProvider.notifier).setSort(album.id, next);
  }
}

class _SortSheet extends StatefulWidget {
  const _SortSheet({required this.current});
  final AlbumSort current;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late AlbumSortBy _by = widget.current.by;
  late bool _reversed = widget.current.reversed;

  @override
  Widget build(BuildContext context) {
    final (String first, String second) = _by.directions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text('Sort', style: Theme.of(context).textTheme.titleLarge),
        ),
        RadioGroup<AlbumSortBy>(
          groupValue: _by,
          onChanged: (AlbumSortBy? v) => setState(() {
            if (v == null) return;
            _by = v;
            _reversed = false;
          }),
          child: Column(
            children: <Widget>[
              for (final AlbumSortBy b in AlbumSortBy.values)
                RadioListTile<AlbumSortBy>(value: b, title: Text(b.label)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: false, label: Text(first)),
              ButtonSegment<bool>(value: true, label: Text(second)),
            ],
            selected: <bool>{_reversed},
            onSelectionChanged: (Set<bool> s) =>
                setState(() => _reversed = s.first),
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
            onPressed: () =>
                Navigator.of(context).pop(AlbumSort(_by, reversed: _reversed)),
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
      .trash(context, items);
  ref.invalidate(albumsProvider);
  return gone.isNotEmpty;
}
