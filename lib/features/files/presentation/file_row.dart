import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/swipe_actions.dart';
import '../domain/file_entry.dart';
import 'files_providers.dart';

/// One line in a folder: icon (or thumbnail), name, size and date. Swipe
/// left for More and Delete; press and hold to start selecting.
///
/// While the folder is selecting, [selected] is non-null: the row shows a
/// tick, a tap toggles it, and a drag that starts on the tick sweeps the
/// rows it passes over.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    required this.onDelete,
    this.selected,
    this.onSweepStart,
    this.onSweepUpdate,
  });

  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final VoidCallback onDelete;

  /// Null when the folder is not selecting.
  final bool? selected;
  final ValueChanged<Offset>? onSweepStart;
  final ValueChanged<Offset>? onSweepUpdate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool selecting = selected != null;
    final bool on = selected ?? false;
    final String meta = entry.isFolder
        ? Fmt.date(entry.modified)
        : '${Fmt.size(entry.size)} · ${Fmt.date(entry.modified)}';
    final Widget row = Material(
      color: on
          ? Color.alphaBlend(cs.primary.withValues(alpha: 0.12), cs.groupedRow)
          : cs.groupedRow,
      child: InkWell(
        onTap: onTap,
        onLongPress: selecting ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              _Tick(
                shown: selecting,
                on: on,
                onSweepStart: onSweepStart,
                onSweepUpdate: onSweepUpdate,
              ),
              FileIcon(entry: entry, size: 36),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: cs.onSurface),
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.isFolder && !selecting)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selecting) {
      return Semantics(
        checked: on,
        inMutuallyExclusiveGroup: false,
        child: row,
      );
    }
    return SwipeActions(
      actions: <SwipeAction>[
        SwipeAction(
          icon: CupertinoIcons.ellipsis_circle,
          label: 'More',
          onTap: onMore,
        ),
        SwipeAction(
          icon: CupertinoIcons.trash,
          label: 'Delete',
          destructive: true,
          onTap: onDelete,
        ),
      ],
      child: Semantics(
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          const CustomSemanticsAction(label: 'Select'): onLongPress,
          const CustomSemanticsAction(label: 'More options'): onMore,
          const CustomSemanticsAction(label: 'Delete'): onDelete,
        },
        child: row,
      ),
    );
  }
}

/// The selection tick, which slides in ahead of the icon. A vertical drag
/// begun on it belongs to the sweep, not to the list's scrolling: the inner
/// recognizer sees each move first and so claims the gesture.
class _Tick extends StatelessWidget {
  const _Tick({
    required this.shown,
    required this.on,
    this.onSweepStart,
    this.onSweepUpdate,
  });

  final bool shown;
  final bool on;
  final ValueChanged<Offset>? onSweepStart;
  final ValueChanged<Offset>? onSweepUpdate;

  static const double _size = 24;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.decelerate,
      width: shown ? _size + AppSpacing.md : 0,
      height: 36,
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: !shown
          ? null
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (DragStartDetails d) =>
                  onSweepStart?.call(d.globalPosition),
              onVerticalDragUpdate: (DragUpdateDetails d) =>
                  onSweepUpdate?.call(d.globalPosition),
              child: SizedBox(
                width: _size + AppSpacing.md,
                height: 36,
                child: Align(
                  alignment: Alignment.centerLeft,
                  // The tick fills in place and swells once as it does.
                  child: Pop(
                    on: on,
                    child: GlyphSwap(
                      icon: on
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: _size,
                      color: on ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class FileIcon extends ConsumerWidget {
  const FileIcon({super.key, required this.entry, this.size = 40});

  final FileEntry entry;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (entry.kind == FileKind.zip) {
      // A comic or photo archive shows one of its own pictures. The box
      // is the icon's size either way, so the picture arriving moves
      // nothing.
      final Uint8List? cover = ref
          .watch(zipCoverProvider((entry.path, entry.size)))
          .value;
      if (cover != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Image.memory(
            cover,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                _box(cs, CupertinoIcons.archivebox, null),
          ),
        );
      }
    }
    if (entry.kind == FileKind.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Image.file(
          File(entry.path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, _, _) => _box(cs, CupertinoIcons.photo, null),
        ),
      );
    }
    final (IconData icon, Color? tint) = switch (entry.kind) {
      FileKind.folder => (CupertinoIcons.folder_fill, cs.primary),
      FileKind.video => (CupertinoIcons.film, null),
      FileKind.pdf => (CupertinoIcons.doc_richtext, cs.error),
      FileKind.zip => (CupertinoIcons.archivebox, null),
      FileKind.text => (CupertinoIcons.doc_text, null),
      _ => (CupertinoIcons.doc, null),
    };
    return _box(cs, icon, tint);
  }

  Widget _box(ColorScheme cs, IconData icon, Color? tint) => SizedBox(
    width: size,
    height: size,
    child: Icon(icon, color: tint ?? cs.onSurfaceVariant, size: size * 0.78),
  );
}
