import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/selection/selection.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import 'files_providers.dart';
import 'files_selection.dart';
import 'files_screen.dart';

/// A pushed folder inside the Files tab: its name as the large title, with
/// the path from Internal storage under it.
class FolderScreen extends ConsumerWidget {
  const FolderScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? root = ref.watch(storageRootProvider).value;
    final String parent = p.dirname(path);
    final String crumb = root == null
        ? path
        : 'Internal storage › ${p.relative(path, from: root).replaceAll('/', ' › ')}';
    final FolderBar bar = folderBar(
      ref,
      path,
      leading: BackBarButton(
        label: root == null || parent == root ? 'Files' : p.basename(parent),
      ),
    );
    return PopScope(
      canPop: !bar.selecting,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) ref.read(selectionProvider.notifier).clear();
      },
      child: LargeTitleScaffold(
        title: p.basename(path),
        subtitle: crumb,
        grouped: true,
        barTitle: bar.barTitle,
        leading: bar.leading,
        trailing: bar.trailing,
        body: (BuildContext context, Widget header) =>
            FolderBody(dir: path, header: header, animateIn: true),
      ),
    );
  }
}
