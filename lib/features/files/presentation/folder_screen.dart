import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'files_providers.dart';
import 'files_screen.dart';

/// A pushed folder inside the Files tab.
class FolderScreen extends ConsumerWidget {
  const FolderScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? root = ref.watch(storageRootProvider).value;
    final String crumb = root == null
        ? path
        : 'Internal storage › ${p.relative(path, from: root).replaceAll('/', ' › ')}';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              p.basename(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              crumb,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[NewFolderButton(dir: path)],
      ),
      body: FolderBody(dir: path),
    );
  }
}
