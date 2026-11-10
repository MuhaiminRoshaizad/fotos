import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/swipe_actions.dart';
import '../domain/file_entry.dart';

/// One line in a folder: icon (or thumbnail), name, size and date. Swipe
/// left for More and Delete, or long-press for every action.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onMore,
    required this.onDelete,
  });

  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String meta = entry.isFolder
        ? Fmt.date(entry.modified)
        : '${Fmt.size(entry.size)} · ${Fmt.date(entry.modified)}';
    return SwipeActions(
      actions: <SwipeAction>[
        SwipeAction(label: 'More', onTap: onMore),
        SwipeAction(label: 'Delete', destructive: true, onTap: onDelete),
      ],
      child: Semantics(
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          const CustomSemanticsAction(label: 'More options'): onMore,
          const CustomSemanticsAction(label: 'Delete'): onDelete,
        },
        child: Material(
          color: cs.groupedRow,
          child: InkWell(
            onTap: onTap,
            onLongPress: () {
              AppHaptics.longPress();
              onMore();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
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
                  if (entry.isFolder)
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
        ),
      ),
    );
  }
}

class FileIcon extends StatelessWidget {
  const FileIcon({super.key, required this.entry, this.size = 40});

  final FileEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
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

  Widget _box(ColorScheme cs, IconData icon, Color? tint) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
    child: Icon(
      icon,
      color: tint ?? cs.onSurfaceVariant,
      size: AppIconSize.dense + 2,
    ),
  );
}
