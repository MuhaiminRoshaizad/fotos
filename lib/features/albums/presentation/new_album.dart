import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/media/media_tile.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';

/// Android shows a folder as an album only once it holds something, so a new
/// album is named first and then filled straight away from a picker.
Future<void> createAlbum(BuildContext context, WidgetRef ref) async {
  final List<Album> albums = await ref.read(albumsProvider.future);
  if (!context.mounted) return;
  final String? name = await promptName(
    context,
    title: 'New album',
    label: 'Album name',
    hint: 'e.g. Holiday 2026',
    confirmLabel: 'Next',
    validate: (String v) =>
        validateFolderName(v, albums.map((Album a) => a.name)),
  );
  if (name == null || !context.mounted) return;
  final List<AssetEntity> library = await ref.read(
    libraryProvider(MediaKind.all).future,
  );
  if (!context.mounted) return;
  final List<AssetEntity>? picked = await showAppSheet<List<AssetEntity>>(
    context,
    scrollControlled: true,
    builder: (_) => _Picker(album: name, items: library),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final bool ok = await ref
      .read(mediaRepositoryProvider)
      .moveTo(picked, 'Pictures/$name/');
  ref.invalidate(albumsProvider);
  ref.invalidate(libraryProvider);
  if (!context.mounted) return;
  if (ok) {
    AppHaptics.success();
    showToast(
      context,
      'Created $name with ${Fmt.count(picked.length, 'item')}',
    );
  } else {
    showToast(context, 'The album wasn\'t created. Nothing was moved.');
  }
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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
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
