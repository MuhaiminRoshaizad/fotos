import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/media/grid_skeleton.dart';
import '../../../core/media/grouping.dart';
import '../../../core/media/media_access_gate.dart';
import '../../../core/media/media_grid.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/media/selection_actions.dart';
import '../../../core/selection/selection.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
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

  @override
  Widget build(BuildContext context) {
    final bool selecting = ref.watch(
      selectionProvider.select((SelectionState s) => s.isActiveFor(_owner)),
    );
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) ref.read(selectionProvider.notifier).clear();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.xs,
                ),
                child: SizedBox(
                  height: 48,
                  child: AnimatedSwitcher(
                    duration: AppMotion.short,
                    child: selecting
                        ? SelectionHeader(
                            allIds: () =>
                                _items.map((AssetEntity e) => e.id).toSet(),
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.kind.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: MediaAccessGate(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.sm,
                        ),
                        child: SegmentedButton<GridLevel>(
                          showSelectedIcon: false,
                          segments: <ButtonSegment<GridLevel>>[
                            for (final GridLevel l in GridLevel.values)
                              ButtonSegment<GridLevel>(
                                value: l,
                                label: Text(l.label),
                              ),
                          ],
                          selected: <GridLevel>{_level},
                          onSelectionChanged: (Set<GridLevel> s) =>
                              setState(() => _level = s.first),
                        ),
                      ),
                      Expanded(child: _body()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final AsyncValue<List<AssetEntity>> items = ref.watch(
      libraryProvider(widget.kind.media),
    );
    return items.when(
      skipLoadingOnRefresh: true,
      loading: () => GridSkeleton(level: _level),
      error: (_, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Couldn\'t load your ${widget.kind.title.toLowerCase()}',
        message: 'Something went wrong reading the photo library.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(libraryProvider(widget.kind.media)),
      ),
      data: (List<AssetEntity> list) {
        if (list.isEmpty) {
          final bool photos = widget.kind == LibraryKind.photos;
          return EmptyState(
            icon: photos
                ? Icons.photo_library_outlined
                : Icons.video_library_outlined,
            title: photos ? 'No photos yet' : 'No videos yet',
            message: photos
                ? 'Photos you take or import appear here.'
                : 'Videos you record or import appear here.',
          );
        }
        _items = list;
        return MediaGrid(
          items: list,
          level: _level,
          heroPrefix: widget.kind.name,
          selectionOwner: _owner,
          selectionActions: () => mediaSelectionActions(
            ref,
            () => _items,
            onViewAlbum: (_) => context.go('/albums'),
          ),
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
