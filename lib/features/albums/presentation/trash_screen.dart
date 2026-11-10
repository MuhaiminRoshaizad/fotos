import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/grid_skeleton.dart';
import '../../../core/media/grouping.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/toast.dart';
import 'albums_providers.dart';

/// Android's trash. Each item shows how long it has left; tap one to restore
/// it or delete it for good.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TrashedItem>> trash = ref.watch(trashProvider);
    final double bottom = AppNavMetrics.clearance(
      MediaQuery.paddingOf(context).bottom,
    );
    final List<TrashedItem> loaded = trash.value ?? const <TrashedItem>[];
    return LargeTitleScaffold(
      title: 'Recently deleted',
      subtitle: trash.hasValue ? Fmt.count(loaded.length, 'item') : '',
      leading: const BackBarButton(label: 'Albums'),
      trailing: <Widget>[
        if (loaded.isNotEmpty)
          BarButton.text(
            label: 'Restore all',
            onPressed: () => _restore(context, ref, loaded),
          ),
      ],
      body: (BuildContext context, Widget header) {
        Widget headed(Widget state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            Expanded(child: state),
          ],
        );
        return trash.when(
          skipLoadingOnRefresh: true,
          loading: () => headed(const GridSkeleton(level: GridLevel.all)),
          error: (_, _) => headed(
            EmptyState(
              icon: CupertinoIcons.exclamationmark_circle,
              title: 'Couldn\'t read the trash',
              message: 'Android didn\'t return the deleted items.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(trashProvider),
            ),
          ),
          data: (List<TrashedItem> items) => items.isEmpty
              ? headed(
                  const EmptyState(
                    icon: CupertinoIcons.trash,
                    title: 'Nothing deleted',
                    message:
                        'Photos and videos you delete stay here for 30 days, '
                        'then Android removes them for good.',
                  ),
                )
              : EntranceScope(
                  child: CustomScrollView(
                    slivers: <Widget>[
                      SliverToBoxAdapter(child: header),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.md,
                          ),
                          child: Text(
                            'Android deletes each item for good when its days '
                            'run out.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                        itemCount: items.length,
                        itemBuilder: (BuildContext context, int i) => SlideUpIn(
                          index: i ~/ 4,
                          child: _TrashTile(
                            item: items[i],
                            onTap: () => _actions(context, ref, items[i]),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: SizedBox(height: bottom)),
                    ],
                  ),
                ),
        );
      },
    );
  }

  static AssetEntity _entity(TrashedItem t) => AssetEntity(
    id: t.id,
    typeInt: t.video ? 2 : 1,
    width: t.width,
    height: t.height,
    isTrashed: true,
  );

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    List<TrashedItem> items,
  ) async {
    final List<String> back = await PhotoManager.editor.android
        .restoreFromTrash(items.map(_entity).toList());
    ref.invalidate(trashProvider);
    ref.invalidate(libraryProvider);
    ref.invalidate(albumsProvider);
    if (context.mounted && back.isNotEmpty) {
      showToast(context, 'Restored ${Fmt.count(back.length, 'item')}');
    }
  }

  Future<void> _actions(
    BuildContext context,
    WidgetRef ref,
    TrashedItem item,
  ) async {
    final String? choice = await showActionSheet<String>(
      context,
      title: item.name,
      message: _left(item),
      choices: const <SheetChoice<String>>[
        SheetChoice<String>('restore', 'Restore'),
        SheetChoice<String>('purge', 'Delete for good', destructive: true),
      ],
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'restore') {
      await _restore(context, ref, <TrashedItem>[item]);
      return;
    }
    // Android shows its own "can't be undone" confirmation for this.
    final bool gone = await ref
        .read(nativeChannelProvider)
        .deleteForever(<String>[item.id], <bool>[item.video]);
    ref.invalidate(trashProvider);
    if (context.mounted && gone) {
      showToast(context, 'Deleted for good');
    }
  }

  static String _left(TrashedItem t) {
    final int days = t.expires.difference(DateTime.now()).inDays;
    if (days <= 0) return 'Deleted for good today';
    return days == 1 ? '1 day left' : '$days days left';
  }
}

class _TrashTile extends ConsumerWidget {
  const _TrashTile({required this.item, required this.onTap});
  final TrashedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '${item.video ? 'Video' : 'Photo'}, ${TrashScreen._left(item)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ColoredBox(
          color: cs.surfaceContainerHigh,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (ref.watch(trashThumbnailProvider(item)).value
                  case final Uint8List bytes)
                Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
              Positioned(
                left: 4,
                bottom: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    child: Text(
                      '${item.expires.difference(DateTime.now()).inDays.clamp(0, 99)} d',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
