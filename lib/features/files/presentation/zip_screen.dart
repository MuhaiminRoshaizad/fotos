import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/format/formatters.dart';
import '../../../core/format/natural_sort.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/toast.dart';
import '../../albums/presentation/albums_providers.dart';
import 'files_providers.dart';

/// Shows the pages inside a comic ZIP as a grid and lets the reader delete the
/// ones they don't want — ads, credits, duplicate covers — rewriting the
/// archive in place so a later extraction is already clean.
class ZipScreen extends ConsumerStatefulWidget {
  const ZipScreen({super.key, required this.path});
  final String path;

  @override
  ConsumerState<ZipScreen> createState() => _ZipScreenState();
}

class _ZipScreenState extends ConsumerState<ZipScreen> {
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  void _setSelecting(bool on) => setState(() {
    _selecting = on;
    if (!on) _selected.clear();
  });

  void _toggle(String name) => setState(() {
    if (!_selected.remove(name)) _selected.add(name);
  });

  Future<void> _deleteSelected(int totalPages) async {
    final int n = _selected.length;
    if (n == 0) return;
    final String name = p.basename(widget.path);
    final bool ok = await confirmAction(
      context,
      title: 'Delete ${Fmt.count(n, 'page')}?',
      message: n == totalPages
          ? 'That is every page. $name is left empty, and this can\'t be undone.'
          : 'The ${n == 1 ? 'page is' : 'pages are'} removed from $name for good. This can\'t be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;

    final List<String> names = _selected.toList();
    final NativeChannel native = ref.read(nativeChannelProvider);
    final ValueNotifier<(int, int)> progress = ValueNotifier<(int, int)>((0, 0));
    final StreamSubscription<(int, int)> sub = native.zipRemoveProgress.listen(
      (v) => progress.value = v,
    );
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (BuildContext ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Removing pages'),
            content: ValueListenableBuilder<(int, int)>(
              valueListenable: progress,
              builder: (_, (int, int) v, _) => LinearProgressIndicator(
                value: v.$2 == 0 ? null : v.$1 / v.$2,
              ),
            ),
          ),
        ),
      ),
    );

    String message;
    bool failed = false;
    try {
      await native.zipRemove(widget.path, names);
      message = 'Removed ${Fmt.count(n, 'page')}';
      AppHaptics.success();
    } on NotEnoughSpaceException catch (e) {
      message = 'Not enough space. Cleaning up needs ${Fmt.size(e.needed)} free.';
      failed = true;
      AppHaptics.error();
    } on Exception {
      message = 'Couldn\'t remove the ${n == 1 ? 'page' : 'pages'}. The ZIP is unchanged.';
      failed = true;
      AppHaptics.error();
    } finally {
      await sub.cancel();
      progress.dispose();
    }

    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!failed) {
      _setSelecting(false);
      ref.invalidate(zipEntriesProvider(widget.path));
    }
    if (mounted) showToast(context, message, failed: failed);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ZipEntry>> entries = ref.watch(
      zipEntriesProvider(widget.path),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selecting
              ? (_selected.isEmpty
                    ? 'Select pages'
                    : Fmt.count(_selected.length, 'selected', 'selected'))
              : p.basename(widget.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          if (entries.value?.isNotEmpty ?? false)
            TextButton(
              onPressed: () => _setSelecting(!_selecting),
              child: Text(_selecting ? 'Cancel' : 'Select'),
            ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          entries.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const EmptyState(
              icon: CupertinoIcons.archivebox,
              title: 'This ZIP can\'t be opened',
              message: 'It may be damaged or protected with a password.',
            ),
            data: (List<ZipEntry> items) {
              if (items.isEmpty) {
                return const EmptyState(
                  icon: CupertinoIcons.archivebox,
                  title: 'No files in this ZIP',
                  message: 'There are no pages left to show.',
                );
              }
              final List<ZipEntry> sorted = List<ZipEntry>.of(items)
                ..sort((ZipEntry a, ZipEntry b) => naturalCompare(a.name, b.name));
              return _Grid(
                path: widget.path,
                entries: sorted,
                selecting: _selecting,
                selected: _selected,
                onToggle: _toggle,
                onLongPressSelect: (String name) {
                  if (!_selecting) _setSelecting(true);
                  _toggle(name);
                },
              );
            },
          ),
          // Floats just above the app's persistent bottom nav: its top sits at
          // height + gap + inset from the bottom, and clearance adds another
          // AppSpacing.lg of air above that.
          if (_selecting && _selected.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: AppNavMetrics.clearance(
                MediaQuery.paddingOf(context).bottom,
              ),
              child: Center(
                child: _DeleteBar(
                  count: _selected.length,
                  onDelete: () => _deleteSelected(entries.value?.length ?? 0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.path,
    required this.entries,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPressSelect,
  });

  final String path;
  final List<ZipEntry> entries;
  final bool selecting;
  final Set<String> selected;
  final void Function(String name) onToggle;
  final void Function(String name) onLongPressSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppNavMetrics.clearance(MediaQuery.paddingOf(context).bottom),
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.72,
      ),
      itemCount: entries.length,
      itemBuilder: (BuildContext context, int i) {
        final ZipEntry e = entries[i];
        return _PageTile(
          path: path,
          entry: e,
          selecting: selecting,
          selected: selected.contains(e.name),
          onTap: selecting ? () => onToggle(e.name) : null,
          onLongPress: () => onLongPressSelect(e.name),
        );
      },
    );
  }
}

class _PageTile extends ConsumerWidget {
  const _PageTile({
    required this.path,
    required this.entry,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final String path;
  final ZipEntry entry;
  final bool selecting;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Widget thumb = entry.isImage
        ? _Thumb(path: path, name: entry.name)
        : Container(
            color: cs.surfaceContainerHigh,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(CupertinoIcons.doc, color: cs.onSurfaceVariant),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  p.basename(entry.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
    return Semantics(
      label: 'Page ${p.basename(entry.name)}',
      selected: selecting ? selected : null,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(color: cs.surfaceContainerHigh),
                child: thumb,
              ),
              if (selecting)
                AnimatedContainer(
                  duration: AppMotion.short,
                  color: selected
                      ? Colors.transparent
                      : Colors.black.withValues(alpha: 0.35),
                ),
              if (selecting)
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: _Check(on: selected),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.path, required this.name});
  final String path;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Uint8List?> bytes = ref.watch(
      zipPageThumbProvider((path, name)),
    );
    final Widget blank = const SizedBox.expand();
    return bytes.when(
      loading: () => blank,
      error: (_, _) => blank,
      data: (Uint8List? data) => data == null
          ? blank
          : Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? cs.primary : Colors.black.withValues(alpha: 0.25),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: on
          ? const Icon(CupertinoIcons.check_mark, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// The floating "Delete (N)" pill shown while pages are selected.
class _DeleteBar extends StatelessWidget {
  const _DeleteBar({required this.count, required this.onDelete});
  final int count;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: <BoxShadow>[
          BoxShadow(
            blurRadius: 16,
            offset: const Offset(0, 6),
            color: Colors.black.withValues(alpha: 0.28),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: onDelete,
        style: FilledButton.styleFrom(
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
        ),
        icon: const Icon(CupertinoIcons.delete, size: AppIconSize.dense),
        label: Text('Delete ($count)'),
      ),
    );
  }
}
