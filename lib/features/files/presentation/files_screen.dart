import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSliverRefreshControl;
import 'package:flutter/gestures.dart'
    show HitTestEntry, HitTestResult, HitTestTarget;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        RenderAbstractViewport,
        RenderMetaData,
        RenderSliverMultiBoxAdaptor,
        SliverConstraints;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/selection/selection.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/swipe_actions.dart';
import '../../albums/presentation/albums_providers.dart';
import '../data/files_repository.dart';
import '../domain/file_entry.dart';
import 'file_actions.dart';
import 'file_row.dart';
import 'file_tile.dart';
import 'files_providers.dart';
import 'files_selection.dart';
import '../../../core/widgets/bottom_bar_space.dart';
import '../../../core/widgets/glide_back_physics.dart';
import '../domain/folder_handle.dart';
import '../../../core/widgets/scroll_handle.dart';

/// The Files tab root: asks for All files access in context, then shows
/// storage use and the top-level folders.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () {
      ref.read(filesAccessProvider.notifier).recheck();
      ref.invalidate(folderProvider);
      ref.invalidate(storageStatsProvider);
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> access = ref.watch(filesAccessProvider);
    final AsyncValue<String> root = ref.watch(storageRootProvider);
    final FolderBar? bar = access.value == true && root.hasValue
        ? folderBar(ref, root.value!)
        : null;
    return PopScope(
      canPop: !(bar?.selecting ?? false),
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) ref.read(selectionProvider.notifier).clear();
      },
      child: LargeTitleScaffold(
        title: 'Files',
        grouped: true,
        barTitle: bar?.barTitle,
        leading: bar?.leading,
        trailing: bar?.trailing ?? const <Widget>[],
        body: (BuildContext context, Widget header) {
          Widget headed(Widget state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
              Expanded(child: state),
            ],
          );
          return switch ((access, root)) {
            (AsyncData<bool>(value: true), AsyncData<String>(:final value)) =>
              FolderBody(
                dir: value,
                header: header,
                preface: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _PinnedGroup(),
                    _StorageGroup(),
                    GroupHeading('Folders'),
                  ],
                ),
              ),
            (AsyncData<bool>(value: false), _) => headed(
              EmptyState(
                icon: CupertinoIcons.folder_open,
                title: 'See every file on your phone',
                message:
                    'Files shows all your folders, including PDFs and ZIPs. '
                    'Android asks you to turn on All files access for fotos '
                    'first. Photos, Videos and Albums work without it.',
                actionLabel: 'Open settings',
                onAction: () => ref
                    .read(nativeChannelProvider)
                    .openAllFilesAccessSettings(),
              ),
            ),
            (AsyncError<bool>(), _) || (_, AsyncError<String>()) => headed(
              EmptyState(
                icon: CupertinoIcons.exclamationmark_circle,
                title: 'Couldn\'t open Files',
                message: 'Android didn\'t answer. Try again.',
                actionLabel: 'Try again',
                onAction: () {
                  ref.invalidate(filesAccessProvider);
                  ref.invalidate(storageRootProvider);
                },
              ),
            ),
            _ => headed(const SizedBox.shrink()),
          };
        },
      ),
    );
  }
}

/// Pinned folders and files, above everything else on the Files tab.
/// Nothing is shown until something is pinned from its More sheet.
class _PinnedGroup extends ConsumerWidget {
  const _PinnedGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? root = ref.watch(storageRootProvider).value;
    final FilesRepository repo = ref.watch(filesRepositoryProvider);
    final List<FileEntry> pins = <FileEntry>[
      for (final String path
          in ref.watch(filesTabPinsProvider).value ?? const <String>[])
        // One deleted since it was added has gone; files belong to Pin to
        // top, not here.
        if (repo.entryAtSync(path) case final FileEntry e when e.isFolder) e,
    ];
    if (pins.isEmpty) return const SizedBox.shrink();
    String where(String path) {
      if (root == null) return '';
      final String rel = p.relative(p.dirname(path), from: root);
      return rel == '.' ? 'Internal storage' : rel.replaceAll('/', ' › ');
    }

    return InsetGroup(
      header: 'Pinned',
      children: <Widget>[
        for (final FileEntry e in pins)
          SwipeActions(
            key: ValueKey<String>(e.path),
            actions: <SwipeAction>[
              SwipeAction(
                icon: CupertinoIcons.pin_slash,
                label: 'Remove',
                onTap: () =>
                    ref.read(filesTabPinsProvider.notifier).toggle(e.path),
              ),
            ],
            // Opaque, or the Unpin action behind the row shows through.
            child: Material(
              color: cs.groupedRow,
              child: GroupRow(
                leading: e.isFolder
                    ? Icon(CupertinoIcons.folder_fill, color: cs.primary)
                    : FileIcon(entry: e, size: 32),
                title: e.name,
                subtitle: root == null ? null : where(e.path),
                chevron: e.isFolder,
                onTap: e.isFolder
                    ? () => context.push(
                        Uri(
                          path: '/files/folder',
                          queryParameters: <String, String>{'path': e.path},
                        ).toString(),
                      )
                    : () => openEntry(context, ref, e, <FileEntry>[e]),
              ),
            ),
          ),
      ],
    );
  }
}

/// Storage use as the first group, iOS Settings style.
class _StorageGroup extends ConsumerWidget {
  const _StorageGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final StorageStats? s = ref.watch(storageStatsProvider).value;
    return InsetGroup(
      header: 'Storage',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: AppSpacing.sm,
                children: <Widget>[
                  const Text(
                    'Internal storage',
                    style: TextStyle(fontSize: 16),
                  ),
                  Text(
                    s == null
                        ? ''
                        : '${Fmt.size(s.used)} of ${Fmt.size(s.total)}',
                    style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: LinearProgressIndicator(
                  value: s == null ? 0 : s.used / s.total,
                  minHeight: 6,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A folder's contents with loading, empty and error states, as one long
/// inset group under [header], with a search field that filters the folder
/// by name and iOS pull-to-refresh.
class FolderBody extends ConsumerStatefulWidget {
  const FolderBody({
    super.key,
    required this.dir,
    required this.header,
    this.preface,
    this.animateIn = false,
  });

  final String dir;
  final Widget header;

  /// Shown between the search field and the rows, and hidden while a search
  /// is typed so results sit directly under the field.
  final Widget? preface;

  /// Rows slide up as they first appear: for a folder the user opened, not
  /// for the Files tab, which is visited too often for motion.
  final bool animateIn;

  @override
  ConsumerState<FolderBody> createState() => _FolderBodyState();
}

class _FolderBodyState extends ConsumerState<FolderBody> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  /// The grid or list of rows, read by the scroll handle to find the row
  /// it has landed on.
  final GlobalKey _rowsKey = GlobalKey();

  /// The handle's label for each row as shown, in the rows' order.
  List<FolderHandleLabel> _handleLabels = const <FolderHandleLabel>[];

  @override
  void initState() {
    super.initState();
    _query.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() {
    ref.read(folderQueryProvider(widget.dir).notifier).set(_query.text);
    setState(() {});
  }

  String get _owner => filesSelectionOwner(widget.dir);

  /// What a sweep is setting the rows it passes to: the opposite of the
  /// row it started on.
  bool? _sweepTo;
  String? _sweepFrom;

  /// The paths on screen, in order, for the sweep to fill between.
  List<String> _shown = const <String>[];

  // Rows that have just gone (moved, deleted) stay for a moment to close
  // up, and rows that have just come open out, so the list is seen to
  // change instead of being replaced.
  List<FileEntry>? _last;
  String _lastQuery = '';
  final Map<String, (int, FileEntry)> _leaving = <String, (int, FileEntry)>{};
  final Set<String> _entering = <String>{};
  Timer? _settle;

  /// [shown] with the rows that are on their way out put back in place.
  List<FileEntry> _withLeaving(List<FileEntry> shown, String query) {
    final List<FileEntry>? last = _last;
    // Typing in the search field filters at once; only a change to the
    // folder itself is animated, and not a wholesale one.
    if (last != null && query == _lastQuery && !identical(last, shown)) {
      final Set<String> now = <String>{for (final FileEntry e in shown) e.path};
      final Set<String> before = <String>{
        for (final FileEntry e in last) e.path,
      };
      final int changed =
          before.difference(now).length + now.difference(before).length;
      if (changed > 0 && changed <= 40) {
        for (int i = 0; i < last.length; i++) {
          if (!now.contains(last[i].path)) {
            _leaving[last[i].path] = (i, last[i]);
          }
        }
        _entering.addAll(now.difference(before));
        _settle?.cancel();
        _settle = Timer(_RowPresence.duration, () {
          if (!mounted) return;
          setState(() {
            _leaving.clear();
            _entering.clear();
          });
        });
      }
    }
    _last = shown;
    _lastQuery = query;
    if (_leaving.isEmpty) return shown;
    final List<FileEntry> rows = List<FileEntry>.of(shown);
    final List<(int, FileEntry)> gone = _leaving.values.toList()
      ..sort(((int, FileEntry) a, (int, FileEntry) b) => a.$1.compareTo(b.$1));
    for (final (int at, FileEntry e) in gone) {
      rows.insert(at.clamp(0, rows.length), e);
    }
    return rows;
  }

  void _startSelecting(String path) {
    AppHaptics.longPress();
    ref
        .read(selectionProvider.notifier)
        .start(
          _owner,
          filesSelectionActions(ref, widget.dir),
          initial: <String>{path},
        );
  }

  void _set(String path, bool on) {
    final Set<String> ids = ref.read(selectionProvider).ids;
    if (ids.contains(path) == on) return;
    ref.read(selectionProvider.notifier).toggle(path);
    AppHaptics.tick();
  }

  String? _pathAt(Offset global) {
    final HitTestResult result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      global,
      View.of(context).viewId,
    );
    for (final HitTestEntry<HitTestTarget> e in result.path) {
      final HitTestTarget t = e.target;
      if (t is RenderMetaData && t.metaData is _RowTag) {
        return (t.metaData as _RowTag).path;
      }
    }
    return null;
  }

  void _sweepStart(String path) {
    _sweepFrom = path;
    _sweepTo = !ref.read(selectionProvider).ids.contains(path);
    _set(path, _sweepTo!);
  }

  /// Sets every row between the one the sweep began on and the one under
  /// the finger, so a fast drag cannot skip the rows it jumped over.
  void _sweepUpdate(Offset global) {
    final String? path = _pathAt(global);
    if (path == null || _sweepTo == null) return;
    final int from = _shown.indexOf(_sweepFrom!);
    final int to = _shown.indexOf(path);
    if (from < 0 || to < 0) return;
    for (int i = from < to ? from : to; i <= (from < to ? to : from); i++) {
      _set(_shown[i], _sweepTo!);
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// How far the bar covers the top of the list.
  double get _underBar => MediaQuery.paddingOf(context).top + kBarHeight;

  /// The handle's label for the row at the top of the screen, under the bar.
  HandleLabel _handleLabel(double offset) {
    final RenderObject? r = _rowsKey.currentContext?.findRenderObject();
    if (r is! RenderSliverMultiBoxAdaptor || _handleLabels.isEmpty) {
      return HandleLabel.none;
    }
    final RenderAbstractViewport viewport = RenderAbstractViewport.of(r);
    final double y = offset + _underBar;
    int index = 0;
    for (RenderBox? c = r.firstChild; c != null; c = r.childAfter(c)) {
      index = r.indexOf(c);
      // The scroll offset that would put this row at the top.
      final double top = viewport.getOffsetToReveal(c, 0).offset;
      if (top + c.size.height > y) break;
    }
    final FolderHandleLabel l =
        _handleLabels[index.clamp(0, _handleLabels.length - 1)];
    return HandleLabel(l.primary, secondary: l.secondary, mark: l.mark);
  }

  /// Where each step (letter, year, size band) starts. Rows and grid lines
  /// all have one height, so a row's place follows from the laid-out ones.
  List<HandleMark> _handleMarks() {
    final RenderObject? r = _rowsKey.currentContext?.findRenderObject();
    if (r is! RenderSliverMultiBoxAdaptor) return const <HandleMark>[];
    final RenderBox? first = r.firstChild;
    if (first == null) return const <HandleMark>[];
    final RenderAbstractViewport viewport = RenderAbstractViewport.of(r);
    double revealOf(RenderBox c) => viewport.getOffsetToReveal(c, 0).offset;
    final double firstTop = revealOf(first);
    final int firstIndex = r.indexOf(first);
    // Tiles in one grid line share a top; the next top gives the stride.
    int perLine = 1;
    double stride = first.size.height;
    for (RenderBox? c = r.childAfter(first); c != null; c = r.childAfter(c)) {
      final double top = revealOf(c);
      if (top == firstTop) {
        perLine++;
      } else {
        stride = top - firstTop;
        break;
      }
    }
    final List<HandleMark> marks = <HandleMark>[];
    final Set<String> seen = <String>{};
    for (int i = 0; i < _handleLabels.length; i++) {
      final String? mark = _handleLabels[i].mark;
      if (mark == null || !seen.add(mark)) continue;
      final double top =
          firstTop + (i ~/ perLine - firstIndex ~/ perLine) * stride;
      marks.add(HandleMark(top - _underBar, mark));
    }
    return marks;
  }

  @override
  Widget build(BuildContext context) {
    final String dir = widget.dir;
    final Widget header = widget.header;
    final AsyncValue<List<FileEntry>> list = ref.watch(folderProvider(dir));
    final SelectionState sel = ref.watch(selectionProvider);
    final bool selecting = sel.isActiveFor(_owner);
    final bool grid = ref.watch(filesGridProvider).value ?? false;
    // The page does not resize for the keyboard, so the list makes room for
    // it itself and the last match can scroll clear.
    final double bottom =
        bottomClearance(context) + MediaQuery.viewInsetsOf(context).bottom;
    Widget headed(Widget state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        Expanded(child: state),
      ],
    );
    return list.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () =>
          _RowsSkeleton(header: header, grid: grid, preface: widget.preface),
      error: (_, _) => headed(
        EmptyState(
          icon: CupertinoIcons.folder_badge_minus,
          title: 'Can\'t open ${p.basename(dir)}',
          message: p.basename(dir) == 'Android'
              ? 'Android protects app data in this folder. Other apps, fotos '
                    'included, can\'t open it.'
              : 'Android didn\'t allow reading this folder.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(folderProvider(dir)),
        ),
      ),
      data: (List<FileEntry> entries) {
        final String q = _query.text.trim();
        // The Files tab's own folders are pinned to its Pinned section, not
        // to the top of the list.
        final Set<String> pins = dir == ref.watch(storageRootProvider).value
            ? const <String>{}
            : <String>{...?ref.watch(topPinsProvider).value};
        final FileSort sort =
            (ref.watch(fileSortsProvider).value ?? const FileSorts()).sortFor(
              dir,
            );
        final List<FileEntry> shown = pinnedFirst(
          sort.apply(filterByName(entries, q)),
          pins,
        );
        _shown = <String>[for (final FileEntry e in shown) e.path];
        final List<FileEntry> rows = _withLeaving(shown, q);
        _handleLabels = folderHandleLabels(
          rows: grid ? shown : rows,
          sort: sort,
          pins: pins,
        );
        final Widget scroll = CustomScrollView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(
            parent: GlideBackPhysics(),
          ),
          slivers: <Widget>[
            SliverToBoxAdapter(child: header),
            CupertinoSliverRefreshControl(
              onRefresh: () => ref.refresh(folderProvider(dir).future),
            ),
            if (entries.isNotEmpty)
              SliverToBoxAdapter(
                child: SearchField(
                  placeholder: 'Search this folder',
                  controller: _query,
                  focus: _focus,
                  active: _focus.hasFocus || _query.text.isNotEmpty,
                ),
              ),
            if (widget.preface != null && q.isEmpty)
              SliverToBoxAdapter(child: widget.preface),
            if (entries.isEmpty)
              const SliverToBoxAdapter(
                child: SizedBox(
                  height: 360,
                  child: EmptyState(
                    icon: CupertinoIcons.folder,
                    title: 'This folder is empty',
                    message:
                        'Files you save or extract here appear in this list.',
                  ),
                ),
              )
            else if (shown.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'Nothing in this folder matches “${_query.text.trim()}”.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else if (grid)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                sliver: SliverLayoutBuilder(
                  builder: (BuildContext context, SliverConstraints c) {
                    // Three across on a phone, more as the page widens.
                    final int columns = (c.crossAxisExtent / 118).floor().clamp(
                      3,
                      8,
                    );
                    final double width =
                        (c.crossAxisExtent - AppSpacing.md * (columns - 1)) /
                        columns;
                    return SliverGrid.builder(
                      key: _rowsKey,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                        mainAxisExtent:
                            width / FileTile.coverAspect +
                            FileTile.labelHeight(context),
                      ),
                      itemCount: shown.length,
                      itemBuilder: (BuildContext context, int i) {
                        final FileEntry e = shown[i];
                        final Widget tile = FileTile(
                          key: ValueKey<String>(e.path),
                          entry: e,
                          selected: selecting ? sel.ids.contains(e.path) : null,
                          pinned: pins.contains(e.path),
                          onTap: selecting
                              ? () => ref
                                    .read(selectionProvider.notifier)
                                    .toggle(e.path)
                              : () => openEntry(context, ref, e, shown),
                          onLongPress: () => _startSelecting(e.path),
                          onMore: () => showEntryActions(context, ref, e),
                        );
                        return widget.animateIn
                            ? SlideUpIn(index: i ~/ columns, child: tile)
                            : tile;
                      },
                    );
                  },
                ),
              )
            else
              SliverList.builder(
                key: _rowsKey,
                itemCount: rows.length,
                itemBuilder: (BuildContext context, int i) {
                  final FileEntry e = rows[i];
                  final Widget row = InsetGroupItem(
                    first: i == 0,
                    last: i == rows.length - 1,
                    child: MetaData(
                      metaData: _RowTag(e.path),
                      child: FileRow(
                        key: ValueKey<String>(e.path),
                        entry: e,
                        selected: selecting ? sel.ids.contains(e.path) : null,
                        pinned: pins.contains(e.path),
                        onTap: selecting
                            ? () => ref
                                  .read(selectionProvider.notifier)
                                  .toggle(e.path)
                            : () => openEntry(context, ref, e, shown),
                        onLongPress: () => _startSelecting(e.path),
                        onSweepStart: (_) => _sweepStart(e.path),
                        onSweepUpdate: _sweepUpdate,
                        onMore: () => showEntryActions(context, ref, e),
                        onDelete: () => deleteEntry(context, ref, e),
                      ),
                    ),
                  );
                  final Widget present = _RowPresence(
                    key: ValueKey<String>('row:${e.path}'),
                    entering: _entering.contains(e.path),
                    leaving: _leaving.containsKey(e.path),
                    child: row,
                  );
                  return widget.animateIn
                      ? SlideUpIn(index: i, child: present)
                      : present;
                },
              ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        );
        // The Files tab's own list stays plain; a folder opened from it
        // can run to hundreds of comics.
        final bool root = dir == ref.watch(storageRootProvider).value;
        return EntranceScope(
          child: root
              ? scroll
              : Stack(
                  children: <Widget>[
                    Positioned.fill(child: scroll),
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + kBarHeight,
                      right: 0,
                      bottom: bottom,
                      child: ScrollHandle(
                        controller: _scroll,
                        semanticLabel: 'Scroll through this folder',
                        labelAt: _handleLabel,
                        marks: _handleMarks,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Opens a row out as it arrives and closes it up as it leaves; a row that
/// is simply there is drawn as it is.
class _RowPresence extends StatefulWidget {
  const _RowPresence({
    super.key,
    required this.entering,
    required this.leaving,
    required this.child,
  });

  final bool entering;
  final bool leaving;
  final Widget child;

  static const Duration duration = Duration(milliseconds: 260);

  @override
  State<_RowPresence> createState() => _RowPresenceState();
}

class _RowPresenceState extends State<_RowPresence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _RowPresence.duration,
    value: widget.entering ? 0 : 1,
  );
  late final Animation<double> _size = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.entering) _c.forward();
    // Built already on its way out, when the list itself was rebuilt.
    if (widget.leaving) _c.reverse();
  }

  @override
  void didUpdateWidget(_RowPresence old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.leaving ? const SizedBox.shrink() : widget.child;
    }
    return IgnorePointer(
      ignoring: widget.leaving,
      child: SizeTransition(
        sizeFactor: _size,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: _c, child: widget.child),
      ),
    );
  }
}

/// Marks a row for the sweep's hit test.
class _RowTag {
  const _RowTag(this.path);
  final String path;
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton({required this.header, required this.grid, this.preface});
  final Widget header;
  final bool grid;
  final Widget? preface;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        header,
        const SearchFieldPlaceholder(),
        ?preface,
        if (grid)
          // The grid view loads as a grid: same columns, same tile shape.
          Skeletonizer(
            enabled: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  final int columns = (c.maxWidth / 118).floor().clamp(3, 8);
                  final double width =
                      (c.maxWidth - AppSpacing.md * (columns - 1)) / columns;
                  return Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: <Widget>[
                      for (int i = 0; i < columns * 3; i++)
                        SizedBox(
                          width: width,
                          height:
                              width / FileTile.coverAspect +
                              FileTile.labelHeight(context),
                          child: Column(
                            children: <Widget>[
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.md,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              const Text(
                                'File name',
                                maxLines: 1,
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          )
        else
          Skeletonizer(
            enabled: true,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < 8; i++)
                  InsetGroupItem(
                    first: i == 0,
                    last: i == 7,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Folder name here',
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 16),
                                ),
                                Text(
                                  '09/11/2026',
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
