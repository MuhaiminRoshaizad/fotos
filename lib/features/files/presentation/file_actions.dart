import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';
import '../../albums/presentation/albums_providers.dart';
import '../domain/file_entry.dart';
import 'file_row.dart';
import 'files_providers.dart';
import 'folder_picker.dart';

/// Opens [entry] the way its type calls for. [siblings] are the folder's
/// entries, so photos and videos can be paged through.
Future<void> openEntry(
  BuildContext context,
  WidgetRef ref,
  FileEntry entry,
  List<FileEntry> siblings,
) async {
  switch (entry.kind) {
    case FileKind.folder:
      context.push(
        Uri(
          path: '/files/folder',
          queryParameters: <String, String>{'path': entry.path},
        ).toString(),
      );
    case FileKind.image:
    case FileKind.video:
      final List<FileEntry> media = siblings
          .where((FileEntry e) => e.isMedia)
          .toList();
      context.push('/files/media', extra: (media, media.indexOf(entry)));
    case FileKind.pdf:
      context.push(
        Uri(
          path: '/files/pdf',
          queryParameters: <String, String>{'path': entry.path},
        ).toString(),
      );
    case FileKind.text:
      context.push(
        Uri(
          path: '/files/text',
          queryParameters: <String, String>{'path': entry.path},
        ).toString(),
      );
    case FileKind.zip:
      await showEntryActions(context, ref, entry);
    case FileKind.other:
      final bool opened = await ref
          .read(nativeChannelProvider)
          .openWith(entry.path);
      if (!opened && context.mounted) {
        showToast(context, 'No app on this phone can open ${entry.name}.');
      }
  }
}

void _refresh(WidgetRef ref) {
  ref.invalidate(folderProvider);
  ref.invalidate(storageStatsProvider);
  ref.invalidate(libraryProvider);
  ref.invalidate(albumsProvider);
}

/// The More sheet for a file or folder.
Future<void> showEntryActions(
  BuildContext context,
  WidgetRef ref,
  FileEntry entry,
) async {
  final NativeChannel native = ref.read(nativeChannelProvider);
  ZipInfo? zip;
  if (entry.kind == FileKind.zip) {
    try {
      zip = await native.zipInfo(entry.path);
    } on Exception {
      zip = null;
    }
    if (!context.mounted) return;
  }
  final String? choice = await showAppSheet<String>(
    context,
    builder: (BuildContext ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          leading: FileIcon(entry: entry),
          title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            entry.kind == FileKind.zip
                ? (zip == null
                      ? 'This ZIP can\'t be read. It may be damaged.'
                      : '${Fmt.size(entry.size)} · ${Fmt.count(zip.files, 'file')} inside')
                : entry.isFolder
                ? Fmt.date(entry.modified)
                : '${Fmt.size(entry.size)} · ${Fmt.date(entry.modified)}',
          ),
        ),
        const Divider(height: 1),
        if (zip != null) ...<Widget>[
          SheetAction(
            icon: Icons.unarchive_outlined,
            label: 'Extract here',
            onTap: () => Navigator.of(ctx).pop('extractHere'),
          ),
          SheetAction(
            icon: Icons.drive_file_move_outlined,
            label: 'Extract to…',
            onTap: () => Navigator.of(ctx).pop('extractTo'),
          ),
        ],
        if (!entry.isFolder) ...<Widget>[
          SheetAction(
            icon: Icons.open_in_new,
            label: 'Open with another app',
            onTap: () => Navigator.of(ctx).pop('openWith'),
          ),
          SheetAction(
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: () => Navigator.of(ctx).pop('share'),
          ),
        ],
        SheetAction(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () => Navigator.of(ctx).pop('rename'),
        ),
        SheetAction(
          icon: Icons.drive_file_move_outlined,
          label: 'Move to…',
          onTap: () => Navigator.of(ctx).pop('move'),
        ),
        SheetAction(
          icon: Icons.copy_outlined,
          label: 'Copy to…',
          onTap: () => Navigator.of(ctx).pop('copy'),
        ),
        SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => Navigator.of(ctx).pop('delete'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'extractHere':
      await _extract(context, ref, entry, p.dirname(entry.path));
    case 'extractTo':
      final String root = await ref.read(storageRootProvider.future);
      if (!context.mounted) return;
      final String? dir = await pickFolder(
        context,
        ref,
        start: p.dirname(entry.path),
        root: root,
        action: 'Extract here',
      );
      if (dir != null && context.mounted) {
        await _extract(context, ref, entry, dir);
      }
    case 'openWith':
      final bool ok = await native.openWith(entry.path);
      if (!ok && context.mounted) {
        showToast(context, 'No app on this phone can open ${entry.name}.');
      }
    case 'share':
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(entry.path)]),
      );
    case 'rename':
      await _rename(context, ref, entry);
    case 'move':
    case 'copy':
      await _transfer(context, ref, entry, move: choice == 'move');
    case 'delete':
      await _delete(context, ref, entry);
  }
}

Future<void> _rename(
  BuildContext context,
  WidgetRef ref,
  FileEntry entry,
) async {
  final Set<String> taken = await ref
      .read(filesRepositoryProvider)
      .namesIn(p.dirname(entry.path));
  if (!context.mounted) return;
  final String? name = await promptName(
    context,
    title: entry.isFolder ? 'Rename folder' : 'Rename file',
    label: 'Name',
    hint: entry.isFolder ? 'e.g. Receipts' : 'e.g. Offer letter.pdf',
    confirmLabel: 'Rename',
    initial: entry.name,
    selectStem: !entry.isFolder,
    validate: (String v) => validateFolderName(v, taken, current: entry.name),
  );
  if (name == null || name == entry.name || !context.mounted) return;
  try {
    await ref.read(filesRepositoryProvider).rename(entry, name);
    _refresh(ref);
    if (context.mounted) showToast(context, 'Renamed to $name');
  } on FileSystemException {
    AppHaptics.error();
    if (context.mounted) showToast(context, 'Couldn\'t rename ${entry.name}.');
  }
}

Future<void> _transfer(
  BuildContext context,
  WidgetRef ref,
  FileEntry entry, {
  required bool move,
}) async {
  final String root = await ref.read(storageRootProvider.future);
  if (!context.mounted) return;
  final String? dir = await pickFolder(
    context,
    ref,
    start: p.dirname(entry.path),
    root: root,
    action: move ? 'Move here' : 'Copy here',
    exclude: entry.isFolder ? entry.path : null,
  );
  if (dir == null || !context.mounted) return;
  if (move && dir == p.dirname(entry.path)) return;
  try {
    final repo = ref.read(filesRepositoryProvider);
    move ? await repo.moveTo(entry, dir) : await repo.copyTo(entry, dir);
    _refresh(ref);
    AppHaptics.success();
    if (context.mounted) {
      showToast(
        context,
        '${move ? 'Moved' : 'Copied'} ${entry.name} to ${p.basename(dir)}',
      );
    }
  } on FileSystemException {
    AppHaptics.error();
    if (context.mounted) {
      showToast(context, 'Couldn\'t ${move ? 'move' : 'copy'} ${entry.name}.');
    }
  }
}

Future<void> _delete(
  BuildContext context,
  WidgetRef ref,
  FileEntry entry,
) async {
  final bool ok = await confirmAction(
    context,
    title: 'Delete ${entry.name}?',
    message: entry.isFolder
        ? 'The folder and everything in it are deleted for good. They don\'t go to Recently deleted.'
        : 'This file is deleted for good. It doesn\'t go to Recently deleted.',
    confirmLabel: 'Delete',
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(filesRepositoryProvider).delete(entry);
    _refresh(ref);
    if (context.mounted) showToast(context, 'Deleted ${entry.name}');
  } on FileSystemException {
    AppHaptics.error();
    if (context.mounted) showToast(context, 'Couldn\'t delete ${entry.name}.');
  }
}

/// Extracts into a new folder named after the ZIP, inside [parent]. Photos
/// and videos inside are scanned, so the folder shows up in Albums.
Future<void> _extract(
  BuildContext context,
  WidgetRef ref,
  FileEntry zip,
  String parent,
) async {
  final repo = ref.read(filesRepositoryProvider);
  final String stem = p.basenameWithoutExtension(zip.name);
  final String folder = uniqueName(stem, await repo.namesIn(parent));
  final String target = p.join(parent, folder);
  if (!context.mounted) return;
  final NativeChannel native = ref.read(nativeChannelProvider);
  final ValueNotifier<(int, int)> progress = ValueNotifier<(int, int)>((0, 0));
  final StreamSubscription<(int, int)> sub = native.extractProgress.listen(
    (v) => progress.value = v,
  );
  final Future<int> work = native.extract(zip.path, target);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (BuildContext ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Extracting ${zip.name}'),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (_, (int, int) v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2),
                const SizedBox(height: AppSpacing.md),
                Text(
                  v.$2 == 0 ? 'Checking space…' : '${v.$1} of ${v.$2} files',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  String message;
  int written = 0;
  try {
    written = await work;
    message = 'Extracted ${Fmt.count(written, 'file')} into $folder';
    AppHaptics.success();
  } on NotEnoughSpaceException catch (e) {
    message = 'Not enough space. Extracting needs ${Fmt.size(e.needed)} free.';
    AppHaptics.error();
  } on Exception {
    message = 'Couldn\'t extract ${zip.name}. It may be damaged.';
    AppHaptics.error();
  } finally {
    await sub.cancel();
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  _refresh(ref);
  if (context.mounted) {
    showToast(
      context,
      message,
      actionLabel: written > 0 ? 'Open' : null,
      onAction: written > 0
          ? () => context.push(
              Uri(
                path: '/files/folder',
                queryParameters: <String, String>{'path': target},
              ).toString(),
            )
          : null,
    );
  }
}
