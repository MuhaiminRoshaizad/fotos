import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/empty_albums.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import 'new_album.dart';

/// An album created with nothing in it yet.
class EmptyAlbumScreen extends ConsumerWidget {
  const EmptyAlbumScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LargeTitleScaffold(
      title: name,
      subtitle: 'Empty',
      leading: const BackBarButton(label: 'Albums'),
      trailing: <Widget>[
        BarButton.icon(
          icon: CupertinoIcons.trash,
          tooltip: 'Delete album',
          onPressed: () async {
            final bool ok = await confirmAction(
              context,
              title: 'Delete $name?',
              message: 'The album is empty, so nothing else is deleted.',
              confirmLabel: 'Delete',
            );
            if (!ok) return;
            await ref.read(emptyAlbumsProvider.notifier).remove(name);
            if (context.mounted) context.pop();
          },
        ),
      ],
      body: (BuildContext context, Widget header) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          Expanded(
            child: EmptyState(
              icon: CupertinoIcons.rectangle_stack,
              title: '$name is empty',
              message: 'Add photos and videos now, or later with Add to album.',
              actionLabel: 'Add photos',
              onAction: () async {
                final bool added = await addPhotosTo(context, ref, name);
                if (added && context.mounted) context.pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}
