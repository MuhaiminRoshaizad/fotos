import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../format/formatters.dart';
import '../haptics/app_haptics.dart';
import '../theme/app_tokens.dart';
import '../validation/validators.dart';
import '../widgets/app_sheet.dart';
import '../widgets/dialogs.dart';
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
  if (relativePath == null) return;

  final MediaRepository repo = ref.read(mediaRepositoryProvider);
  final bool move = choice.move;
  int done;
  if (move) {
    done = await repo.moveTo(items, relativePath) ? items.length : 0;
  } else {
    done = await repo.copyTo(items, relativePath);
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
  AppHaptics.success();
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Text(
              'Add ${Fmt.count(widget.count, 'item')} to album',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('Move')),
                ButtonSegment<bool>(value: false, label: Text('Copy')),
              ],
              selected: <bool>{_move},
              onSelectionChanged: (Set<bool> s) =>
                  setState(() => _move = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              _move
                  ? 'Moves the files into the album\'s folder. Uses no extra space.'
                  : 'Makes a second copy in the album. Uses extra space.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
          ListTile(
            leading: _Thumb(
              child: Icon(CupertinoIcons.plus, color: cs.primary),
            ),
            title: const Text('New album'),
            onTap: () => Navigator.of(context).pop(_Choice(null, _move)),
          ),
          for (final String n in widget.empty)
            ListTile(
              leading: const _Thumb(
                child: Icon(CupertinoIcons.rectangle_stack),
              ),
              title: Text(n),
              subtitle: const Text('Empty'),
              onTap: () =>
                  Navigator.of(context).pop(_Choice(null, _move, emptyName: n)),
            ),
          for (final Album a in widget.albums)
            ListTile(
              leading: _Thumb(
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
              title: Text(a.name),
              subtitle: Text(Fmt.count(a.count, 'item')),
              onTap: () => Navigator.of(context).pop(_Choice(a, _move)),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadii.sm),
    child: SizedBox(
      width: 48,
      height: 48,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: child,
      ),
    ),
  );
}
