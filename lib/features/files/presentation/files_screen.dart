import 'dart:io';

import 'package:flutter/cupertino.dart'
    show
        CupertinoButton,
        CupertinoIcons,
        CupertinoSearchTextField,
        CupertinoSliverRefreshControl;
import 'package:flutter/gestures.dart'
    show HitTestEntry, HitTestResult, HitTestTarget;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/selection/selection.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/swipe_actions.dart';
import '../../../core/widgets/toast.dart';
import '../../albums/presentation/albums_providers.dart';
import '../domain/file_entry.dart';
import 'file_actions.dart';
import 'file_row.dart';
import 'files_providers.dart';
import 'files_selection.dart';

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

/// Pinned folders, above everything else on the Files tab. Nothing is
/// shown until a folder is pinned from its More sheet.
class _PinnedGroup extends ConsumerWidget {
  const _PinnedGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? root = ref.watch(storageRootProvider).value;
    final List<String> pins = <String>[
      for (final String path
          in ref.watch(pinnedFoldersProvider).value ?? const <String>[])
        // A folder deleted or renamed since it was pinned has gone.
        if (Directory(path).existsSync()) path,
    ];
    if (pins.isEmpty) return const SizedBox.shrink();
    return InsetGroup(
      header: 'Pinned',
      children: <Widget>[
        for (final String path in pins)
          SwipeActions(
            key: ValueKey<String>(path),
            actions: <SwipeAction>[
              SwipeAction(
                icon: CupertinoIcons.pin_slash,
                label: 'Unpin',
                onTap: () =>
                    ref.read(pinnedFoldersProvider.notifier).toggle(path),
              ),
            ],
            // Opaque, or the Unpin action behind the row shows through.
            child: Material(
              color: cs.groupedRow,
              child: GroupRow(
                leading: Icon(CupertinoIcons.folder_fill, color: cs.primary),
                title: p.basename(path),
                subtitle: root == null
                    ? null
                    : p.relative(p.dirname(path), from: root) == '.'
                    ? 'Internal storage'
                    : p
                          .relative(p.dirname(path), from: root)
                          .replaceAll('/', ' › '),
                onTap: () => context.push(
                  Uri(
                    path: '/files/folder',
                    queryParameters: <String, String>{'path': path},
                  ).toString(),
                ),
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

class NewFolderButton extends ConsumerWidget {
  const NewFolderButton({super.key, required this.dir});
  final String dir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BarButton.icon(
      icon: CupertinoIcons.folder_badge_plus,
      tooltip: 'New folder',
      onPressed: () async {
        final List<FileEntry> here =
            ref.read(folderProvider(dir)).value ?? const <FileEntry>[];
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
        await ref.read(filesRepositoryProvider).createFolder(dir, name);
        ref.invalidate(folderProvider(dir));
        if (context.mounted) showToast(context, 'Created $name');
      },
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

  @override
  void initState() {
    super.initState();
    _query.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() => setState(() {});

  String get _owner => filesSelectionOwner(widget.dir);

  /// What a sweep is setting the rows it passes to: the opposite of the
  /// row it started on.
  bool? _sweepTo;
  String? _sweepFrom;

  /// The paths on screen, in order, for the sweep to fill between.
  List<String> _shown = const <String>[];

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
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String dir = widget.dir;
    final Widget header = widget.header;
    final AsyncValue<List<FileEntry>> list = ref.watch(folderProvider(dir));
    final SelectionState sel = ref.watch(selectionProvider);
    final bool selecting = sel.isActiveFor(_owner);
    // The page does not resize for the keyboard, so the list makes room for
    // it itself and the last match can scroll clear.
    final double bottom =
        AppNavMetrics.clearance(MediaQuery.paddingOf(context).bottom) +
        MediaQuery.viewInsetsOf(context).bottom;
    Widget headed(Widget state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        Expanded(child: state),
      ],
    );
    return list.when(
      skipLoadingOnRefresh: true,
      loading: () => _RowsSkeleton(header: header, preface: widget.preface),
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
        final String q = _query.text.trim().toLowerCase();
        final List<FileEntry> shown = q.isEmpty
            ? entries
            : entries
                  .where((FileEntry e) => e.name.toLowerCase().contains(q))
                  .toList();
        _shown = <String>[for (final FileEntry e in shown) e.path];
        return EntranceScope(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: <Widget>[
              SliverToBoxAdapter(child: header),
              CupertinoSliverRefreshControl(
                onRefresh: () => ref.refresh(folderProvider(dir).future),
              ),
              if (entries.isNotEmpty)
                SliverToBoxAdapter(
                  child: _SearchField(
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
              else
                SliverList.builder(
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int i) {
                    final FileEntry e = shown[i];
                    final Widget row = InsetGroupItem(
                      first: i == 0,
                      last: i == shown.length - 1,
                      child: MetaData(
                        metaData: _RowTag(e.path),
                        child: FileRow(
                          key: ValueKey<String>(e.path),
                          entry: e,
                          selected: selecting ? sel.ids.contains(e.path) : null,
                          onTap: selecting
                              ? () => ref
                                    .read(selectionProvider.notifier)
                                    .toggle(e.path)
                              : () => openEntry(context, ref, e, entries),
                          onLongPress: () => _startSelecting(e.path),
                          onSweepStart: (_) => _sweepStart(e.path),
                          onSweepUpdate: _sweepUpdate,
                          onMore: () => showEntryActions(context, ref, e),
                          onDelete: () => deleteEntry(context, ref, e),
                        ),
                      ),
                    );
                    return widget.animateIn
                        ? SlideUpIn(index: i, child: row)
                        : row;
                  },
                ),
              SliverToBoxAdapter(child: SizedBox(height: bottom)),
            ],
          ),
        );
      },
    );
  }
}

/// Marks a row for the sweep's hit test.
class _RowTag {
  const _RowTag(this.path);
  final String path;
}

/// iOS's search field, with Cancel sliding in beside it while it is in use.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.active,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool active;

  static const double height = 36;
  static const EdgeInsets padding = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.xs,
    AppSpacing.lg,
    AppSpacing.sm,
  );

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height),
              child: CupertinoSearchTextField(
                controller: controller,
                focusNode: focus,
                placeholder: 'Search this folder',
                style: TextStyle(fontSize: 16, color: cs.onSurface),
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.decelerate,
            alignment: Alignment.centerLeft,
            child: active
                ? CupertinoButton(
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    minimumSize: const Size(44, 44),
                    onPressed: () {
                      controller.clear();
                      focus.unfocus();
                    },
                    child: const Text('Cancel'),
                  )
                : const SizedBox(height: 44),
          ),
        ],
      ),
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton({required this.header, this.preface});
  final Widget header;
  final Widget? preface;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        header,
        // Stands in for the search field, so nothing moves when it arrives.
        Padding(
          padding: _SearchField.padding,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: Container(
              height: _SearchField.height,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ),
        ?preface,
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
