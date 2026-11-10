import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../domain/file_entry.dart';
import 'files_providers.dart';

/// Lets the user walk folders and confirm one. Returns its path.
/// [exclude] keeps a folder from being moved into itself.
Future<String?> pickFolder(
  BuildContext context,
  WidgetRef ref, {
  required String start,
  required String root,
  required String action,
  String? exclude,
}) {
  return showAppSheet<String>(
    context,
    scrollControlled: true,
    builder: (_) => _FolderPicker(
      start: start,
      root: root,
      action: action,
      exclude: exclude,
    ),
  );
}

class _FolderPicker extends ConsumerStatefulWidget {
  const _FolderPicker({
    required this.start,
    required this.root,
    required this.action,
    this.exclude,
  });

  final String start;
  final String root;
  final String action;
  final String? exclude;

  @override
  ConsumerState<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends ConsumerState<_FolderPicker> {
  late String _dir = widget.start;

  bool get _atRoot => p.equals(_dir, widget.root);

  String get _label => _atRoot
      ? 'Internal storage'
      : p.relative(_dir, from: widget.root).replaceAll('/', ' › ');

  Future<void> _newFolder(List<FileEntry> here) async {
    final String? name = await promptName(
      context,
      title: 'New folder',
      label: 'Folder name',
      hint: 'e.g. Receipts',
      confirmLabel: 'Create',
      validate: (String v) =>
          validateFolderName(v, here.map((FileEntry e) => e.name)),
    );
    if (name == null) return;
    final String made = await ref
        .read(filesRepositoryProvider)
        .createFolder(_dir, name);
    ref.invalidate(folderProvider(_dir));
    setState(() => _dir = made);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<FileEntry>> list = ref.watch(folderProvider(_dir));
    final List<FileEntry> folders = (list.value ?? const <FileEntry>[])
        .where((FileEntry e) => e.isFolder && e.path != widget.exclude)
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                // Kept in place at the root, dimmed, so the title stays
                // centred as the user walks in and out.
                BarButton.icon(
                  icon: CupertinoIcons.chevron_up,
                  tooltip: 'Up one folder',
                  onPressed: _atRoot
                      ? null
                      : () => setState(() => _dir = p.dirname(_dir)),
                ),
                Expanded(
                  child: Text(
                    _label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                BarButton.icon(
                  icon: CupertinoIcons.folder_badge_plus,
                  tooltip: 'New folder',
                  onPressed: () =>
                      _newFolder(list.value ?? const <FileEntry>[]),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isLoading && !list.hasValue
                ? const SizedBox.shrink()
                : folders.isEmpty
                ? Center(
                    child: Text(
                      'No folders here',
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: EdgeInsets.zero,
                    itemCount: folders.length,
                    itemBuilder: (BuildContext context, int i) =>
                        InsetGroupItem(
                          first: i == 0,
                          last: i == folders.length - 1,
                          child: GroupRow(
                            leading: const Icon(CupertinoIcons.folder_fill),
                            title: folders[i].name,
                            onTap: () => setState(() => _dir = folders[i].path),
                          ),
                        ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_dir),
              child: Text(widget.action),
            ),
          ),
        ],
      ),
    );
  }
}
