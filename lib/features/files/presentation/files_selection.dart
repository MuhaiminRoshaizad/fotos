import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/selection/selection.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../domain/file_entry.dart';
import 'file_actions.dart';
import 'files_providers.dart';

/// The selection owner for the folder at [dir]. Selected ids are paths.
String filesSelectionOwner(String dir) => 'files:$dir';

/// The selection bar for a folder: Move, Copy, Share and Delete, each run
/// once for everything selected.
List<SelectionAction> filesSelectionActions(WidgetRef ref, String dir) {
  List<FileEntry> picked(Set<String> paths) => <FileEntry>[
    for (final FileEntry e
        in ref.read(folderProvider(dir)).value ?? const <FileEntry>[])
      if (paths.contains(e.path)) e,
  ];
  void done(bool finished) {
    if (finished) ref.read(selectionProvider.notifier).clear();
  }

  return <SelectionAction>[
    SelectionAction(
      icon: CupertinoIcons.folder,
      label: 'Move',
      run: (BuildContext context, Set<String> ids) async =>
          done(await transferEntries(context, ref, picked(ids), move: true)),
    ),
    SelectionAction(
      icon: CupertinoIcons.doc_on_doc,
      label: 'Copy',
      run: (BuildContext context, Set<String> ids) async =>
          done(await transferEntries(context, ref, picked(ids), move: false)),
    ),
    SelectionAction(
      icon: CupertinoIcons.square_arrow_up,
      label: 'Share',
      run: (BuildContext context, Set<String> ids) async =>
          done(await shareEntries(context, picked(ids))),
    ),
    SelectionAction(
      icon: CupertinoIcons.trash,
      label: 'Delete',
      destructive: true,
      run: (BuildContext context, Set<String> ids) async =>
          done(await deleteEntries(context, ref, picked(ids))),
    ),
  ];
}

/// What a folder page puts in its bar: Select and New folder, or, while
/// selecting, Select all, the count and Done.
class FolderBar {
  const FolderBar({
    required this.selecting,
    required this.barTitle,
    required this.leading,
    required this.trailing,
  });

  final bool selecting;
  final String? barTitle;
  final Widget? leading;
  final List<Widget> trailing;
}

/// [leading] is the page's own leading button, kept while not selecting.
FolderBar folderBar(WidgetRef ref, String dir, {Widget? leading}) {
  final String owner = filesSelectionOwner(dir);
  final SelectionState sel = ref.watch(selectionProvider);
  // What the page is showing: the folder, narrowed by its search field.
  final List<FileEntry> entries = filterByName(
    ref.watch(folderProvider(dir)).value ?? const <FileEntry>[],
    ref.watch(folderQueryProvider(dir)),
  );
  final SelectionNotifier selection = ref.read(selectionProvider.notifier);
  if (!sel.isActiveFor(owner)) {
    return FolderBar(
      selecting: false,
      barTitle: null,
      leading: leading,
      trailing: <Widget>[
        BarButton.text(
          label: 'Select',
          onPressed: entries.isEmpty
              ? null
              : () => selection.start(owner, filesSelectionActions(ref, dir)),
        ),
        FolderMoreButton(dir: dir),
      ],
    );
  }
  final int n = sel.ids.length;
  final bool all =
      entries.isNotEmpty &&
      entries.every((FileEntry e) => sel.ids.contains(e.path));
  return FolderBar(
    selecting: true,
    barTitle: n == 0 ? 'Select items' : '$n selected',
    leading: BarButton.text(
      label: all ? 'Deselect all' : 'Select all',
      // Adds or removes what is shown, keeping anything picked before
      // the search was typed.
      onPressed: () {
        final Set<String> shown = entries.map((FileEntry e) => e.path).toSet();
        selection.setIds(
          all ? sel.ids.difference(shown) : sel.ids.union(shown),
        );
      },
    ),
    trailing: <Widget>[
      BarButton.text(
        label: 'Done',
        prominent: true,
        onPressed: selection.clear,
      ),
    ],
  );
}

/// The ⋯ button of a folder's bar, opening [showFolderMenu].
class FolderMoreButton extends ConsumerWidget {
  const FolderMoreButton({super.key, required this.dir});
  final String dir;

  @override
  Widget build(BuildContext context, WidgetRef ref) => BarButton.icon(
    icon: CupertinoIcons.ellipsis,
    tooltip: 'More',
    onPressed: () => showFolderMenu(context, ref, dir),
  );
}
