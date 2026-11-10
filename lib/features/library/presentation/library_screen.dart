import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoMenuAnchor, CupertinoMenuItem;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/grid_skeleton.dart';
import '../../../core/media/grouping.dart';
import '../../../core/media/media_access_gate.dart';
import '../../../core/media/media_grid.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/media/selection_actions.dart';
import '../../../core/selection/selection.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../viewer/presentation/viewer_screen.dart';

enum LibraryKind {
  photos(MediaKind.photos, 'Photos'),
  videos(MediaKind.videos, 'Videos');

  const LibraryKind(this.media, this.title);
  final MediaKind media;
  final String title;
}

/// The Photos or Videos tab: every item of that kind, newest first.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, required this.kind});

  final LibraryKind kind;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  GridLevel _level = GridLevel.all;
  List<AssetEntity> _items = const <AssetEntity>[];

  String get _owner => widget.kind.name;

  List<SelectionAction> _actions() => mediaSelectionActions(
    ref,
    () => _items,
    onViewAlbum: (String name) async {
      final List<Album> albums = await ref.read(albumsProvider.future);
      final Album? a = albums.where((Album x) => x.name == name).firstOrNull;
      if (!mounted) return;
      context.go(a == null ? '/albums' : '/albums/folder/${a.id}');
    },
  );

  @override
  Widget build(BuildContext context) {
    final SelectionState sel = ref.watch(selectionProvider);
    final bool selecting = sel.isActiveFor(_owner);
    final SelectionNotifier selection = ref.read(selectionProvider.notifier);
    final List<AssetEntity>? loaded = ref
        .watch(libraryProvider(widget.kind.media))
        .value;
    final int? count = loaded?.length;
    final bool photos = widget.kind == LibraryKind.photos;
    final int n = sel.ids.length;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) selection.clear();
      },
      child: LargeTitleScaffold(
        title: widget.kind.title,
        // Always present, so the title block keeps its height while loading.
        subtitle: count == null
            ? ''
            : Fmt.count(count, photos ? 'photo' : 'video'),
        barTitle: selecting ? (n == 0 ? 'Select items' : '$n selected') : null,
        leading: selecting
            ? BarButton.text(
                label: 'Select all',
                onPressed: () => selection.setIds(
                  _items.map((AssetEntity e) => e.id).toSet(),
                ),
              )
            : null,
        trailing: selecting
            ? <Widget>[
                BarButton.text(
                  label: 'Done',
                  prominent: true,
                  onPressed: selection.clear,
                ),
              ]
            : <Widget>[
                BarButton.text(
                  label: 'Select',
                  onPressed: (loaded?.isEmpty ?? true)
                      ? null
                      : () => selection.start(_owner, _actions()),
                ),
                _LevelMenu(
                  level: _level,
                  onChanged: (GridLevel l) => setState(() => _level = l),
                ),
              ],
        body: (BuildContext context, Widget header) =>
            MediaAccessGate(header: header, builder: _body),
      ),
    );
  }

  Widget _body(Widget header) {
    final AsyncValue<List<AssetEntity>> items = ref.watch(
      libraryProvider(widget.kind.media),
    );
    Widget headed(Widget state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        Expanded(child: state),
      ],
    );
    return items.when(
      skipLoadingOnRefresh: true,
      loading: () => headed(GridSkeleton(level: _level)),
      error: (_, _) => headed(
        EmptyState(
          icon: CupertinoIcons.exclamationmark_circle,
          title: 'Couldn\'t load your ${widget.kind.title.toLowerCase()}',
          message: 'Something went wrong reading the photo library.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(libraryProvider(widget.kind.media)),
        ),
      ),
      data: (List<AssetEntity> list) {
        if (list.isEmpty) {
          final bool photos = widget.kind == LibraryKind.photos;
          return headed(
            EmptyState(
              icon: photos
                  ? CupertinoIcons.photo_on_rectangle
                  : CupertinoIcons.play_rectangle,
              title: photos ? 'No photos yet' : 'No videos yet',
              message: photos
                  ? 'Photos you take or import appear here.'
                  : 'Videos you record or import appear here.',
            ),
          );
        }
        _items = list;
        return MediaGrid(
          items: list,
          level: _level,
          header: header,
          overlayTop: MediaQuery.paddingOf(context).top + kBarHeight,
          heroPrefix: widget.kind.name,
          selectionOwner: _owner,
          selectionActions: _actions,
          onLevelChanged: (GridLevel l) => setState(() => _level = l),
          onOpen: (int index) => context.push(
            '/viewer',
            extra: ViewerArgs(
              items: list,
              index: index,
              heroPrefix: widget.kind.name,
            ),
          ),
        );
      },
    );
  }
}

/// How dense the grid is. Pinching changes it too; this is the visible way in.
class _LevelMenu extends StatelessWidget {
  const _LevelMenu({required this.level, required this.onChanged});

  final GridLevel level;
  final ValueChanged<GridLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoMenuAnchor(
      menuChildren: <Widget>[
        for (final GridLevel l in GridLevel.values)
          CupertinoMenuItem(
            onPressed: () => onChanged(l),
            trailing: l == level
                ? const Icon(CupertinoIcons.checkmark, size: 18)
                : null,
            child: Text(l.label),
          ),
      ],
      builder: (BuildContext context, MenuController menu, Widget? child) =>
          BarButton.icon(
            icon: CupertinoIcons.square_grid_2x2,
            tooltip: 'Grid size',
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          ),
    );
  }
}
