import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/empty_albums.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/media/media_tile.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';

/// Names a new album and creates it empty; photos can be added straight
/// away from the album, or later with Add to album.
Future<void> createAlbum(BuildContext context, WidgetRef ref) async {
  final List<Album> albums = await ref.read(albumsProvider.future);
  final List<String> empty = await ref.read(emptyAlbumsProvider.future);
  if (!context.mounted) return;
  final String? name = await promptName(
    context,
    title: 'New album',
    label: 'Album name',
    hint: 'e.g. Holiday 2026',
    confirmLabel: 'Create',
    validate: (String v) => validateFolderName(v, <String>[
      ...albums.map((Album a) => a.name),
      ...empty,
    ]),
  );
  if (name == null || !context.mounted) return;
  await ref.read(emptyAlbumsProvider.notifier).add(name);
  if (!context.mounted) return;
  showToast(context, 'Created $name');
  context.push(
    Uri(
      path: '/albums/empty',
      queryParameters: <String, String>{'name': name},
    ).toString(),
  );
}

/// Picks photos and videos from the library and moves them into [name].
/// Returns whether anything moved.
Future<bool> addPhotosTo(
  BuildContext context,
  WidgetRef ref,
  String name,
) async {
  final List<AssetEntity> library = await ref.read(
    libraryProvider(MediaKind.all).future,
  );
  if (!context.mounted) return false;
  final List<AssetEntity>? picked = await showAppSheet<List<AssetEntity>>(
    context,
    scrollControlled: true,
    builder: (_) => _Picker(album: name, items: library),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return false;
  final bool ok = await ref
      .read(mediaRepositoryProvider)
      .moveTo(picked, albumFolder(name));
  ref.invalidate(albumsProvider);
  ref.invalidate(libraryProvider);
  if (ok) await ref.read(emptyAlbumsProvider.notifier).remove(name);
  if (!context.mounted) return ok;
  if (ok) {
    AppHaptics.success();
    showToast(context, 'Moved ${Fmt.count(picked.length, 'item')} to $name');
  } else {
    showToast(context, 'Nothing was moved.', failed: true);
  }
  return ok;
}

class _Picker extends StatefulWidget {
  const _Picker({required this.album, required this.items});
  final String album;
  final List<AssetEntity> items;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final Set<String> _ids = <String>{};

  @override
  Widget build(BuildContext context) {
    return DraggableSheet(
      initialSize: 0.85,
      maxSize: 0.95,
      builder: (BuildContext context, ScrollController scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              'Add to ${widget.album}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: widget.items.isEmpty
                ? const Center(child: Text('There are no photos to add yet.'))
                : GridView.builder(
                    controller: scroll,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                    itemCount: widget.items.length,
                    itemBuilder: (BuildContext context, int i) {
                      final AssetEntity e = widget.items[i];
                      final bool on = _ids.contains(e.id);
                      return GestureDetector(
                        onTap: () => setState(
                          () => on ? _ids.remove(e.id) : _ids.add(e.id),
                        ),
                        child: MediaTile(
                          asset: e,
                          heroTag: 'picker-${e.id}',
                          selecting: true,
                          selected: on,
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FilledButton(
              onPressed: _ids.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      widget.items
                          .where((AssetEntity e) => _ids.contains(e.id))
                          .toList(),
                    ),
              child: Text(
                _ids.isEmpty
                    ? 'Pick photos to move'
                    : 'Move ${Fmt.count(_ids.length, 'item')}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
