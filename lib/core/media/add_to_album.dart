import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../format/formatters.dart';
import '../theme/app_tokens.dart';
import '../validation/validators.dart';
import '../widgets/app_sheet.dart';
import '../widgets/batch_progress.dart';
import '../widgets/dialogs.dart';
import '../widgets/inset_group.dart';
import '../widgets/toast.dart';
import '../../features/albums/data/album_prefs.dart';
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
  // The sheet opens at once and loads the albums itself, with placeholder
  // rows meanwhile: with 120 albums, loading first kept the tap waiting
  // over a second for anything to happen.
  final _Choice? choice = await showAppSheet<_Choice>(
    context,
    scrollControlled: true,
    builder: (BuildContext ctx) => _AddToAlbumSheet(count: items.length),
  );
  if (choice == null || !context.mounted) return;

  String? relativePath = choice.album == null
      ? (choice.emptyName == null ? null : albumFolder(choice.emptyName!))
      : await choice.album!.path.relativePathAsync;
  if (!context.mounted) return;
  String name = choice.album?.name ?? choice.emptyName ?? '';
  if (choice.album == null && choice.emptyName == null) {
    final List<Album> albums = await ref.read(albumsProvider.future);
    final List<String> empty = pendingEmptyAlbums(
      await ref.read(emptyAlbumsProvider.future),
      albums,
    );
    if (!context.mounted) return;
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

class _AddToAlbumSheet extends ConsumerStatefulWidget {
  const _AddToAlbumSheet({required this.count});
  final int count;

  @override
  ConsumerState<_AddToAlbumSheet> createState() => _AddToAlbumSheetState();
}

/// One line of the sheet's album list, built only when scrolled to.
sealed class _Line {
  const _Line();
}

class _Heading extends _Line {
  const _Heading(this.text);
  final String text;
}

class _Gap extends _Line {
  const _Gap();
}

class _Row extends _Line {
  const _Row({
    required this.first,
    required this.last,
    this.album,
    this.emptyName,
  });
  final bool first;
  final bool last;
  final Album? album;
  final String? emptyName;
}

class _Placeholder extends _Line {
  const _Placeholder({required this.first, required this.last});
  final bool first;
  final bool last;
}

class _AddToAlbumSheetState extends ConsumerState<_AddToAlbumSheet> {
  bool _move = true;

  static const double _indent = 14 + AlbumThumb.size + AppSpacing.md;

  /// The album list as lines: pinned albums under their heading in pin
  /// order, then empty albums and the rest in the Albums tab's order.
  List<_Line> _lines(List<Album> albums, List<String> empty, AlbumPrefs prefs) {
    final List<Album> pinned = <Album>[
      for (final String id in prefs.pinned)
        ...albums.where((Album a) => a.id == id),
    ];
    // Android hands albums over in no order at all.
    final List<Album> rest = prefs.order.apply(
      albums.where((Album a) => !prefs.pinned.contains(a.id)).toList(),
    );
    final bool headed = pinned.isNotEmpty;
    final int others = empty.length + rest.length;
    return <_Line>[
      if (headed) ...<_Line>[
        const _Heading('Pinned'),
        for (int i = 0; i < pinned.length; i++)
          _Row(first: i == 0, last: i == pinned.length - 1, album: pinned[i]),
      ],
      if (others > 0) ...<_Line>[
        if (headed) const _Heading('Albums') else const _Gap(),
        for (int i = 0; i < empty.length; i++)
          _Row(first: i == 0, last: i == others - 1, emptyName: empty[i]),
        for (int i = 0; i < rest.length; i++)
          _Row(
            first: empty.isEmpty && i == 0,
            last: empty.length + i == others - 1,
            album: rest[i],
          ),
      ],
    ];
  }

  /// Rows the size of real ones, while the albums load.
  static const List<_Line> _loading = <_Line>[
    _Gap(),
    _Placeholder(first: true, last: false),
    _Placeholder(first: false, last: false),
    _Placeholder(first: false, last: false),
    _Placeholder(first: false, last: false),
    _Placeholder(first: false, last: true),
  ];

  Widget _albumRow(Album a) => GroupRow(
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
              gaplessPlayback: true,
            ),
    ),
    leadingWidth: AlbumThumb.size,
    title: a.name,
    subtitle: Fmt.count(a.count, 'item'),
    chevron: false,
    onTap: () => Navigator.of(context).pop(_Choice(a, _move)),
  );

  Widget _line(_Line line) => switch (line) {
    _Heading(:final String text) => GroupHeading(text),
    _Gap() => const SizedBox(height: AppSpacing.lg),
    _Placeholder(:final bool first, :final bool last) => Skeletonizer(
      child: InsetGroupItem(
        first: first,
        last: last,
        dividerIndent: _indent,
        child: const GroupRow(
          leading: AlbumThumb(child: SizedBox.expand()),
          leadingWidth: AlbumThumb.size,
          title: 'Album name',
          subtitle: '12 items',
          chevron: false,
        ),
      ),
    ),
    _Row(:final bool first, :final bool last, :final Album? album) =>
      InsetGroupItem(
        first: first,
        last: last,
        dividerIndent: _indent,
        child: album != null
            ? _albumRow(album)
            : GroupRow(
                leading: const AlbumThumb(
                  child: Icon(CupertinoIcons.rectangle_stack),
                ),
                leadingWidth: AlbumThumb.size,
                title: line.emptyName!,
                subtitle: 'Empty',
                chevron: false,
                onTap: () => Navigator.of(
                  context,
                ).pop(_Choice(null, _move, emptyName: line.emptyName)),
              ),
      ),
  };

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<Album>? albums = ref.watch(albumsProvider).value;
    final List<String>? empty = ref.watch(emptyAlbumsProvider).value;
    final AlbumPrefs? prefs = ref.watch(albumPrefsProvider).value;
    final List<_Line> lines = albums == null || empty == null || prefs == null
        ? _loading
        : _lines(albums, pendingEmptyAlbums(empty, albums), prefs);
    final List<Widget> top = <Widget>[
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
    ];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      // Only the rows on screen are built, thumbnails included: a phone
      // with a hundred albums opens the sheet as fast as one with three.
      builder: (BuildContext context, ScrollController scroll) =>
          ListView.builder(
            controller: scroll,
            itemCount: top.length + lines.length + 1,
            itemBuilder: (BuildContext context, int i) {
              if (i < top.length) return top[i];
              if (i == top.length + lines.length) {
                return const SizedBox(height: AppSpacing.lg);
              }
              return _line(lines[i - top.length]);
            },
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
