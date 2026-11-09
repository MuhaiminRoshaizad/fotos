import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/file_entry.dart';

/// One line in a folder: icon (or thumbnail), name, date and size, and a
/// More button for the actions sheet.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onMore,
  });

  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String meta = entry.isFolder
        ? Fmt.date(entry.modified)
        : '${Fmt.size(entry.size)} · ${Fmt.date(entry.modified)}';
    return ListTile(
      onTap: onTap,
      onLongPress: onMore,
      leading: FileIcon(entry: entry),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(meta),
      trailing: IconButton(
        tooltip: 'More options for ${entry.name}',
        onPressed: onMore,
        icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
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
          errorBuilder: (_, _, _) => _box(cs, Icons.image_outlined, null),
        ),
      );
    }
    final (IconData icon, Color? tint) = switch (entry.kind) {
      FileKind.folder => (Icons.folder_outlined, cs.primary),
      FileKind.video => (Icons.movie_outlined, null),
      FileKind.pdf => (Icons.picture_as_pdf_outlined, cs.error),
      FileKind.zip => (Icons.folder_zip_outlined, null),
      FileKind.text => (Icons.description_outlined, null),
      _ => (Icons.insert_drive_file_outlined, null),
    };
    return _box(cs, icon, tint);
  }

  Widget _box(ColorScheme cs, IconData icon, Color? tint) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: tint == cs.primary ? cs.primaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
    child: Icon(
      icon,
      color: tint ?? cs.onSurfaceVariant,
      size: AppIconSize.dense + 2,
    ),
  );
}
