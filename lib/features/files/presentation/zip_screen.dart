import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/natural_sort.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/selection/selection.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/batch_progress.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/toast.dart';
import '../../albums/presentation/albums_providers.dart';
import 'files_providers.dart';

/// Shows the pages inside a comic ZIP as a grid. Tap a page to see it large;
/// select pages to delete the ones you don't want (ads, credits, duplicate
/// covers), which rewrites the archive in place so a later extraction is
/// already clean.
class ZipScreen extends ConsumerWidget {
  const ZipScreen({super.key, required this.path});
  final String path;

  String get _owner => 'zip:$path';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ZipEntry>> entries = ref.watch(
      zipEntriesProvider(path),
    );
    final List<ZipEntry> pages = zipPagesInOrder(
      entries.value ?? const <ZipEntry>[],
    );
    final SelectionState sel = ref.watch(selectionProvider);
    final SelectionNotifier selection = ref.read(selectionProvider.notifier);
    final bool selecting = sel.isActiveFor(_owner);
    final bool all =
        pages.isNotEmpty &&
        pages.every((ZipEntry e) => sel.ids.contains(e.name));

    void startSelecting([String? first]) => selection.start(
      _owner,
      <SelectionAction>[
        SelectionAction(
          icon: CupertinoIcons.trash,
          label: 'Delete',
          destructive: true,
          run: (BuildContext context, Set<String> ids) async {
            if (await removeZipPages(context, ref, path, ids, pages.length)) {
              selection.clear();
            }
          },
        ),
      ],
      initial: <String>{?first},
    );

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) selection.clear();
      },
      child: LargeTitleScaffold(
        title: p.basename(path),
        subtitle: entries.hasValue
            ? '${Fmt.count(pages.length, 'page')} · '
                  '${Fmt.size(pages.fold(0, (int s, ZipEntry e) => s + e.size))}'
            : null,
        barTitle: selecting
            ? (sel.ids.isEmpty ? 'Select pages' : '${sel.ids.length} selected')
            : null,
        leading: selecting
            ? BarButton.text(
                label: all ? 'Deselect all' : 'Select all',
                onPressed: () => selection.setIds(
                  all
                      ? const <String>{}
                      : <String>{for (final ZipEntry e in pages) e.name},
                ),
              )
            : BackBarButton(label: p.basename(p.dirname(path))),
        trailing: <Widget>[
          if (selecting)
            BarButton.text(
              label: 'Done',
              prominent: true,
              onPressed: selection.clear,
            )
          else
            BarButton.text(
              label: 'Select',
              onPressed: pages.isEmpty ? null : startSelecting,
            ),
        ],
        body: (BuildContext context, Widget header) => entries.when(
          skipLoadingOnRefresh: true,
          loading: () => _Headed(header: header, child: const _PagesSkeleton()),
          error: (_, _) => _Headed(
            header: header,
            child: const EmptyState(
              icon: CupertinoIcons.archivebox,
              title: 'This ZIP can\'t be opened',
              message: 'It may be damaged or protected with a password.',
            ),
          ),
          data: (_) => pages.isEmpty
              ? _Headed(
                  header: header,
                  child: const EmptyState(
                    icon: CupertinoIcons.archivebox,
                    title: 'No files in this ZIP',
                    message: 'There are no pages left to show.',
                  ),
                )
              : _PageGrid(
                  header: header,
                  path: path,
                  pages: pages,
                  selected: selecting ? sel.ids : null,
                  onTap: (int i) => selecting
                      ? selection.toggle(pages[i].name)
                      : showZipPage(context, path, pages, i),
                  onLongPress: (int i) => selecting
                      ? selection.toggle(pages[i].name)
                      : startSelecting(pages[i].name),
                ),
        ),
      ),
    );
  }
}

/// A ZIP's files in reading order: natural name order, so page 2 comes
/// before page 10.
List<ZipEntry> zipPagesInOrder(List<ZipEntry> entries) =>
    List<ZipEntry>.of(entries)
      ..sort((ZipEntry a, ZipEntry b) => naturalCompare(a.name, b.name));

/// Asks, then removes [names] from the ZIP at [path] behind the shared
/// progress dialog. [total] is how many pages it holds. Returns whether the
/// pages were removed.
Future<bool> removeZipPages(
  BuildContext context,
  WidgetRef ref,
  String path,
  Set<String> names,
  int total,
) async {
  final int n = names.length;
  if (n == 0) return false;
  final String name = p.basename(path);
  final bool ok = await confirmAction(
    context,
    title: 'Delete ${Fmt.count(n, 'page')}?',
    message: n == total
        ? 'That is every page. $name is left empty, and this can\'t be '
              'undone.'
        : 'The ${n == 1 ? 'page is' : 'pages are'} removed from $name for '
              'good. This can\'t be undone.',
    confirmLabel: 'Delete',
  );
  if (!ok || !context.mounted) return false;
  final NativeChannel native = ref.read(nativeChannelProvider);
  Exception? error;
  final int failed = await runBatch<Set<String>>(
    context,
    verb: 'Removing',
    doneVerb: 'Removed',
    what: Fmt.count(n, 'page'),
    items: <Set<String>>[names],
    progress: native.zipRemoveProgress,
    each: (Set<String> names) async {
      try {
        await native.zipRemove(path, names.toList());
      } on Exception catch (e) {
        error = e;
        rethrow;
      }
    },
  );
  ref.invalidate(zipEntriesProvider(path));
  ref.invalidate(folderProvider(p.dirname(path)));
  if (!context.mounted) return failed == 0;
  if (failed == 0) {
    showToast(context, 'Removed ${Fmt.count(n, 'page')}');
  } else {
    final Exception? e = error;
    showToast(
      context,
      e is NotEnoughSpaceException
          ? 'Not enough space. Removing pages needs ${Fmt.size(e.needed)} '
                'free.'
          : 'Couldn\'t remove the ${n == 1 ? 'page' : 'pages'}. $name is '
                'unchanged.',
      failed: true,
    );
  }
  return failed == 0;
}

class _Headed extends StatelessWidget {
  const _Headed({required this.header, required this.child});
  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      header,
      Expanded(child: child),
    ],
  );
}

/// Three across on a phone, more as the page widens; pages are portrait.
const double _pageAspect = 0.72;
const double _pageMaxWidth = 130;

SliverGridDelegate get _pageGrid =>
    const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: _pageMaxWidth,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: _pageAspect,
    );

class _PageGrid extends StatelessWidget {
  const _PageGrid({
    required this.header,
    required this.path,
    required this.pages,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Widget header;
  final String path;
  final List<ZipEntry> pages;

  /// Null when not selecting.
  final Set<String>? selected;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onLongPress;

  @override
  Widget build(BuildContext context) {
    return EntranceScope(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(child: header),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppNavMetrics.clearance(MediaQuery.paddingOf(context).bottom),
            ),
            sliver: SliverGrid.builder(
              gridDelegate: _pageGrid,
              itemCount: pages.length,
              itemBuilder: (BuildContext context, int i) => SlideUpIn(
                index: i ~/ 3,
                child: _PageTile(
                  key: ValueKey<String>(pages[i].name),
                  path: path,
                  entry: pages[i],
                  selected: selected?.contains(pages[i].name),
                  onTap: () => onTap(i),
                  onLongPress: () => onLongPress(i),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.path,
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final String path;
  final ZipEntry entry;

  /// Null when not selecting.
  final bool? selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool selecting = selected != null;
    final bool on = selected ?? false;
    final String name = p.basename(entry.name);
    return Semantics(
      button: true,
      checked: selecting ? on : null,
      label: 'Page $name',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            AnimatedScale(
              scale: on ? 0.9 : 1,
              duration: AppMotion.short,
              curve: Curves.easeOut,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: ColoredBox(
                  color: cs.surfaceContainerHigh,
                  child: entry.isImage
                      ? _Thumb(path: path, name: entry.name, px: 300)
                      : _NotAPicture(name: name),
                ),
              ),
            ),
            if (selecting)
              Positioned(
                right: 6,
                top: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Pop(
                    on: on,
                    child: GlyphSwap(
                      icon: on
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 24,
                      color: on ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotAPicture extends StatelessWidget {
  const _NotAPicture({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(CupertinoIcons.doc, color: cs.onSurfaceVariant),
          const SizedBox(height: AppSpacing.xs),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({
    required this.path,
    required this.name,
    required this.px,
    this.fit = BoxFit.cover,
  });
  final String path;
  final String name;
  final int px;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Uint8List? bytes = ref
        .watch(zipPageThumbProvider((path, name, px)))
        .value;
    return bytes == null
        ? const SizedBox.expand()
        : Image.memory(bytes, fit: fit, gaplessPlayback: true);
  }
}

/// Placeholder pages the size of real ones while the archive is read.
class _PagesSkeleton extends StatelessWidget {
  const _PagesSkeleton();

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Skeletonizer(
      enabled: true,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          0,
        ),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: _pageGrid,
        itemCount: 12,
        itemBuilder: (_, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
    );
  }
}

/// Shows [pages] full screen from page [index], one at a time; swipe to
/// turn, pinch to zoom.
void showZipPage(
  BuildContext context,
  String path,
  List<ZipEntry> pages,
  int index,
) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: AppMotion.medium,
      reverseTransitionDuration: AppMotion.short,
      pageBuilder: (_, _, _) =>
          _PageViewer(path: path, pages: pages, index: index),
      transitionsBuilder: (_, Animation<double> a, _, Widget child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

class _PageViewer extends StatefulWidget {
  const _PageViewer({
    required this.path,
    required this.pages,
    required this.index,
  });

  final String path;
  final List<ZipEntry> pages;
  final int index;

  @override
  State<_PageViewer> createState() => _PageViewerState();
}

class _PageViewerState extends State<_PageViewer> {
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _at = widget.index;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ZipEntry e = widget.pages[_at];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pages,
            itemCount: widget.pages.length,
            onPageChanged: (int i) => setState(() => _at = i),
            itemBuilder: (BuildContext context, int i) {
              final ZipEntry page = widget.pages[i];
              return InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: page.isImage
                      ? _Thumb(
                          path: widget.path,
                          name: page.name,
                          px: 1600,
                          fit: BoxFit.contain,
                        )
                      : _NotAPicture(name: p.basename(page.name)),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: <Widget>[
                  BarButton.icon(
                    icon: CupertinoIcons.xmark,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '${p.basename(e.name)} · ${_at + 1} of '
                      '${widget.pages.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
