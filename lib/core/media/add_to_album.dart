import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../format/formatters.dart';
import '../theme/app_tokens.dart';
import '../validation/validators.dart';
import '../widgets/app_sheet.dart';
import '../widgets/batch_progress.dart';
import '../widgets/dialogs.dart';
import '../widgets/inset_group.dart';
import '../widgets/toast.dart';
import 'empty_albums.dart';
import 'media_providers.dart';
import 'media_repository.dart';

/// Puts [items] into an existing or new album. Move is the default because it
/// uses no extra space; Copy makes a second file.
Future<void> addToAlbum(
  BuildContext context,
  WidgetRef ref,
  List<AssetEntity> items, {
  VoidCallback? onDone,
  void Function(String albumName)? onView,
}) async {
  final List<Album> albums = await ref.read(albumsProvider.future);
  final List<String> empty = pendingEmptyAlbums(
    await ref.read(emptyAlbumsProvider.future),
    albums,
  );
  if (!context.mounted) return;
  final _Choice? choice = await showAppSheet<_Choice>(
    context,
    scrollControlled: true,
    builder: (BuildContext ctx) =>
        _AddToAlbumSheet(count: items.length, albums: albums, empty: empty),
  );
  if (choice == null || !context.mounted) return;

  String? relativePath = choice.album == null
      ? (choice.emptyName == null ? null : albumFolder(choice.emptyName!))
      : await choice.album!.path.relativePathAsync;
  if (!context.mounted) return;
  String name = choice.album?.name ?? choice.emptyName ?? '';
  if (choice.album == null && choice.emptyName == null) {
    final String? n = await promptName(
      context,
      title: 'New album',
      label: 'Album name',
      hint: 'e.g. Holiday 2026',
      confirmLabel: 'Create',
      validate: (String v) => validateFolderName(v, <String>[
        ...albums.map((Album a) => a.name),
        ...empty,
      ]),
    );
    if (n == null || !context.mounted) return;
    name = n;
    relativePath = albumFolder(n);
  }
  if (relativePath == null || !context.mounted) return;
  // A local the closures below can rely on being set.
  final String target = relativePath;

  final MediaRepository repo = ref.read(mediaRepositoryProvider);
  final bool move = choice.move;
  final String what = Fmt.count(items.length, 'item');
  int done;
  if (move) {
    // Android moves the whole set in one request, so there is nothing to
    // count: the bar runs until it answers.
    final int failed = await runBatch<List<AssetEntity>>(
      context,
      verb: 'Moving',
      doneVerb: 'Moved',
      what: what,
      items: <List<AssetEntity>>[items],
      each: (List<AssetEntity> all) async {
        if (!await repo.moveTo(all, target)) {
          throw Exception('not moved');
        }
      },
    );
    done = failed == 0 ? items.length : 0;
  } else {
    final int failed = await runBatch<AssetEntity>(
      context,
      verb: 'Copying',
      doneVerb: 'Copied',
      what: what,
      items: items,
      nameOf: (AssetEntity e) => e.title ?? '',
      each: (AssetEntity e) async {
        if (await repo.copyTo(<AssetEntity>[e], target) == 0) {
          throw Exception('not copied');
        }
      },
    );
    done = items.length - failed;
  }
  ref.invalidate(libraryProvider);
  ref.invalidate(albumsProvider);
  // Once something has moved in, Android lists the folder itself.
  if (done > 0) await ref.read(emptyAlbumsProvider.notifier).remove(name);
  onDone?.call();
  if (!context.mounted) return;
  if (done == 0) {
    showToast(
      context,
      move ? 'Nothing was moved.' : 'Nothing was copied.',
      failed: true,
    );
    return;
  }
  showToast(
    context,
    '${move ? 'Moved' : 'Copied'} ${Fmt.count(done, 'item')} to $name',
    actionLabel: onView == null ? null : 'View',
    onAction: onView == null ? null : () => onView(name),
  );
}

class _Choice {
  const _Choice(this.album, this.move, {this.emptyName});
  final Album? album;
  final bool move;
  final String? emptyName;
}

/// Empty albums not yet backed by a folder that holds media.
List<String> pendingEmptyAlbums(List<String> empty, List<Album> albums) {
  final Set<String> real = albums
      .map((Album a) => a.name.toLowerCase())
      .toSet();
  return empty.where((String n) => !real.contains(n.toLowerCase())).toList();
}

class _AddToAlbumSheet extends StatefulWidget {
  const _AddToAlbumSheet({
    required this.count,
    required this.albums,
    required this.empty,
  });
  final int count;
  final List<Album> albums;
  final List<String> empty;

  @override
  State<_AddToAlbumSheet> createState() => _AddToAlbumSheetState();
}

class _AddToAlbumSheetState extends State<_AddToAlbumSheet> {
  bool _move = true;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (BuildContext context, ScrollController scroll) => ListView(
        controller: scroll,
        children: <Widget>[
          SheetTitle('Add to album', subtitle: Fmt.count(widget.count, 'item')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: CupertinoSlidingSegmentedControl<bool>(
              groupValue: _move,
              children: const <bool, Widget>{
                true: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Move'),
                ),
                false: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Copy'),
                ),
              },
              onValueChanged: (bool? v) {
                if (v != null) setState(() => _move = v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.sm,
              AppSpacing.xxl,
              AppSpacing.lg,
            ),
            child: Text(
              _move
                  ? 'Moves the files into the album\'s folder. Uses no extra space.'
                  : 'Makes a second copy in the album. Uses extra space.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
          InsetGroup(
            children: <Widget>[
              GroupRow(
                leading: const Icon(CupertinoIcons.plus),
                leadingWidth: AlbumThumb.size,
                title: 'New album',
                chevron: false,
                onTap: () => Navigator.of(context).pop(_Choice(null, _move)),
              ),
            ],
          ),
          if (widget.empty.isNotEmpty || widget.albums.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            InsetGroup(
              dividerIndent: 14 + AlbumThumb.size + AppSpacing.md,
              children: <Widget>[
                for (final String n in widget.empty)
                  GroupRow(
                    leading: const AlbumThumb(
                      child: Icon(CupertinoIcons.rectangle_stack),
                    ),
                    leadingWidth: AlbumThumb.size,
                    title: n,
                    subtitle: 'Empty',
                    chevron: false,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_Choice(null, _move, emptyName: n)),
                  ),
                for (final Album a in widget.albums)
                  GroupRow(
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
                    subtitle: Fmt.count(a.count, 'item'),
                    chevron: false,
                    onTap: () => Navigator.of(context).pop(_Choice(a, _move)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// An album's small square picture in a list of albums.
class AlbumThumb extends StatelessWidget {
  const AlbumThumb({super.key, required this.child});
  final Widget child;

  static const double size = 44;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadii.sm),
    child: SizedBox(
      width: size,
      height: size,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: child,
      ),
    ),
  );
}
