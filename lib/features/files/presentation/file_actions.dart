import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/natural_sort.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/batch_progress.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';
import '../../albums/data/album_prefs.dart';
import '../../albums/presentation/albums_providers.dart';
import '../domain/file_entry.dart';
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
        showToast(
          context,
          'No app on this phone can open ${entry.name}.',
          failed: true,
        );
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
  final bool pinned = (ref.read(pinnedProvider).value ?? const <String>[])
      .contains(entry.path);
  final String? choice = await showActionSheet<String>(
    context,
    title: entry.name,
    message: entry.kind == FileKind.zip
        ? (zip == null
              ? "This ZIP can't be read. It may be damaged."
              : '${Fmt.size(entry.size)} · ${Fmt.count(zip.files, 'file')} inside')
        : entry.isFolder
        ? Fmt.date(entry.modified)
        : '${Fmt.size(entry.size)} · ${Fmt.date(entry.modified)}',
    choices: <SheetChoice<String>>[
      if (zip != null && zip.takeout)
        const SheetChoice<String>('takeout', 'Import from Google Takeout'),
      if (zip != null && !zip.takeout) ...const <SheetChoice<String>>[
        SheetChoice<String>('extractHere', 'Extract here'),
        SheetChoice<String>('extractTo', 'Extract to…'),
      ],
      if (!entry.isFolder) ...const <SheetChoice<String>>[
        SheetChoice<String>('openWith', 'Open with another app'),
        SheetChoice<String>('share', 'Share'),
      ],
      SheetChoice<String>('pin', pinned ? 'Unpin from Files' : 'Pin to Files'),
      const SheetChoice<String>('rename', 'Rename'),
      const SheetChoice<String>('move', 'Move to…'),
      const SheetChoice<String>('copy', 'Copy to…'),
      const SheetChoice<String>('delete', 'Delete', destructive: true),
    ],
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'takeout':
      context.push(
        Uri(
          path: '/takeout/import',
          queryParameters: <String, String>{'path': entry.path},
        ).toString(),
      );
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
        showToast(
          context,
          'No app on this phone can open ${entry.name}.',
          failed: true,
        );
      }
    case 'share':
      await shareEntries(context, <FileEntry>[entry]);
    case 'pin':
      await ref.read(pinnedProvider.notifier).toggle(entry.path);
      if (context.mounted) {
        showToast(
          context,
          pinned ? 'Unpinned ${entry.name}' : 'Pinned ${entry.name} to Files',
        );
      }
    case 'rename':
      await _rename(context, ref, entry);
    case 'move':
    case 'copy':
      await transferEntries(context, ref, <FileEntry>[
        entry,
      ], move: choice == 'move');
    case 'delete':
      await deleteEntry(context, ref, entry);
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
    if (context.mounted) {
      showToast(context, 'Couldn\'t rename ${entry.name}.', failed: true);
    }
  }
}

/// "report.pdf" for one entry, "5 items" for several.
String describeEntries(List<FileEntry> entries) => entries.length == 1
    ? entries.single.name
    : Fmt.count(entries.length, 'item');

/// Shares files through Android's sheet. Folders can't be shared; returns
/// false, having said so, when one is among [entries].
Future<bool> shareEntries(BuildContext context, List<FileEntry> entries) async {
  if (entries.isEmpty) return false;
  if (entries.any((FileEntry e) => e.isFolder)) {
    showToast(
      context,
      'Folders can\'t be shared. Deselect them first.',
      failed: true,
    );
    return false;
  }
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[for (final FileEntry e in entries) XFile(e.path)],
    ),
  );
  return true;
}

/// Asks for a folder once, then moves or copies every entry into it.
/// Returns whether anything was attempted.
Future<bool> transferEntries(
  BuildContext context,
  WidgetRef ref,
  List<FileEntry> entries, {
  required bool move,
}) async {
  if (entries.isEmpty) return false;
  final String from = p.dirname(entries.first.path);
  final String root = await ref.read(storageRootProvider.future);
  if (!context.mounted) return false;
  final String? dir = await pickFolder(
    context,
    ref,
    start: from,
    root: root,
    action: move ? 'Move here' : 'Copy here',
    exclude: <String>{
      for (final FileEntry e in entries)
        if (e.isFolder) e.path,
    },
  );
  if (dir == null || !context.mounted) return false;
  if (move && dir == from) return false;
  final repo = ref.read(filesRepositoryProvider);
  final Set<String> taken = await repo.namesIn(dir);
  if (!context.mounted) return false;
  // One file moves at once; a copy of any size is worth showing.
  final bool shown = entries.length > 1 || !move;
  final int failed = await runBatch<FileEntry>(
    context,
    verb: move ? 'Moving' : 'Copying',
    doneVerb: move ? 'Moved' : 'Copied',
    what: describeEntries(entries),
    items: entries,
    nameOf: (FileEntry e) => e.name,
    show: shown,
    each: (FileEntry e) => move
        ? repo.moveTo(e, dir, taken: taken)
        : repo.copyTo(e, dir, taken: taken),
  );
  _refresh(ref);
  // The dialog gives its own tick and buzz when it is shown.
  if (!shown) failed == 0 ? AppHaptics.success() : AppHaptics.error();
  if (context.mounted) {
    final String what = describeEntries(entries);
    showToast(
      context,
      failed == 0
          ? '${move ? 'Moved' : 'Copied'} $what to ${p.basename(dir)}'
          : entries.length == 1
          ? 'Couldn\'t ${move ? 'move' : 'copy'} $what.'
          : 'Couldn\'t ${move ? 'move' : 'copy'} $failed of $what.',
      failed: failed > 0,
    );
  }
  return true;
}

/// Asks, then deletes [entry] for good (files have no system trash).
Future<void> deleteEntry(
  BuildContext context,
  WidgetRef ref,
  FileEntry entry,
) => deleteEntries(context, ref, <FileEntry>[entry]);

/// Asks once, then deletes every entry for good. Returns whether the user
/// confirmed.
Future<bool> deleteEntries(
  BuildContext context,
  WidgetRef ref,
  List<FileEntry> entries,
) async {
  if (entries.isEmpty) return false;
  final bool one = entries.length == 1;
  final bool folders = entries.any((FileEntry e) => e.isFolder);
  final String what = describeEntries(entries);
  final bool ok = await confirmAction(
    context,
    title: 'Delete $what?',
    message: one
        ? (folders
              ? 'The folder and everything in it are deleted for good. They don\'t go to Recently deleted.'
              : 'This file is deleted for good. It doesn\'t go to Recently deleted.')
        : (folders
              ? 'These items, and everything inside the folders, are deleted for good. They don\'t go to Recently deleted.'
              : 'These files are deleted for good. They don\'t go to Recently deleted.'),
    confirmLabel: 'Delete',
  );
  if (!ok || !context.mounted) return false;
  final repo = ref.read(filesRepositoryProvider);
  final int failed = await runBatch<FileEntry>(
    context,
    verb: 'Deleting',
    doneVerb: 'Deleted',
    what: describeEntries(entries),
    items: entries,
    nameOf: (FileEntry e) => e.name,
    show: entries.length > 1,
    each: repo.delete,
  );
  _refresh(ref);
  if (failed > 0 && entries.length == 1) AppHaptics.error();
  if (context.mounted) {
    showToast(
      context,
      failed == 0
          ? 'Deleted $what'
          : one
          ? 'Couldn\'t delete $what.'
          : 'Couldn\'t delete $failed of $what.',
      failed: failed > 0,
    );
  }
  return true;
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
  // Best-effort, after the toast so feedback is immediate: point the new
  // album's cover at the comic's first page.
  if (written > 0) await _coverExtractedComic(ref, target);
}

/// Sets the cover of the album Android forms from a freshly extracted comic to
/// its first page — the first image by natural name, the page the ZIP showed —
/// unless the user has already chosen a cover for it. Best-effort: a comic
/// Android has not finished indexing simply keeps its default cover.
Future<void> _coverExtractedComic(WidgetRef ref, String target) async {
  try {
    // Every image under the extracted folder; a comic's pages may be flat or
    // sit inside one folder.
    final List<String> images = <String>[
      await for (final FileSystemEntity e in Directory(
        target,
      ).list(recursive: true, followLinks: false))
        if (e is File) e.path,
    ];
    final String? pageOne = firstImagePath(images);
    if (pageOne == null) return;
    final String folder = p.dirname(pageOne); // the album's folder on disk
    final String name = p.basename(folder);
    // Let MediaStore see the new pages so they form an album.
    await ref.read(nativeChannelProvider).scan(images);
    final String root = await ref.read(storageRootProvider.future);
    final String rel = _trimSlashes(p.relative(folder, from: root));
    // Android indexes in the background; give the album a few tries to appear.
    Album? album;
    for (int tries = 0; tries < 12 && album == null; tries++) {
      if (tries > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      ref.invalidate(albumsProvider);
      for (final Album a in await ref.read(albumsProvider.future)) {
        final String? r = await a.path.relativePathAsync;
        if (a.name == name && r != null && _trimSlashes(r) == rel) {
          album = a;
          break;
        }
      }
    }
    if (album == null) return;
    // Only fill an empty cover; never override one the user chose.
    final AlbumPrefs prefs = await ref.read(albumPrefsProvider.future);
    if (prefs.covers.containsKey(album.id)) return;
    final List<AssetEntity> items = await ref
        .read(mediaRepositoryProvider)
        .albumItems(album);
    if (items.isEmpty) return;
    final String want = p.basename(pageOne);
    final AssetEntity first = items.firstWhere(
      (AssetEntity a) => (a.title ?? '') == want,
      orElse: () =>
          (List<AssetEntity>.of(items)..sort(
                (AssetEntity a, AssetEntity b) =>
                    naturalCompare(a.title ?? '', b.title ?? ''),
              ))
              .first,
    );
    await ref.read(albumPrefsProvider.notifier).setCover(album.id, first.id);
  } on Object {
    // A cover is a nicety; never let it break an extraction that worked.
  }
}

/// A relative path without leading or trailing slashes, so a filesystem path
/// and photo_manager's (which carries a trailing slash) compare equal.
String _trimSlashes(String s) => s.replaceAll(RegExp(r'^/+|/+$'), '');
