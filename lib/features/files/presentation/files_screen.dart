import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format/formatters.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/toast.dart';
import '../../albums/presentation/albums_providers.dart';
import '../domain/file_entry.dart';
import 'file_actions.dart';
import 'file_row.dart';
import 'files_providers.dart';

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
    return LargeTitleScaffold(
      title: 'Files',
      grouped: true,
      trailing: <Widget>[
        if (access.value == true && root.hasValue)
          NewFolderButton(dir: root.value!),
      ],
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
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  header,
                  const _StorageGroup(),
                  const GroupHeading('Folders'),
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
              onAction: () =>
                  ref.read(nativeChannelProvider).openAllFilesAccessSettings(),
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
/// inset group under [header], with iOS pull-to-refresh.
class FolderBody extends ConsumerWidget {
  const FolderBody({
    super.key,
    required this.dir,
    required this.header,
    this.animateIn = false,
  });

  final String dir;
  final Widget header;

  /// Rows slide up as they first appear: for a folder the user opened, not
  /// for the Files tab, which is visited too often for motion.
  final bool animateIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FileEntry>> list = ref.watch(folderProvider(dir));
    final double bottom = AppNavMetrics.clearance(
      MediaQuery.paddingOf(context).bottom,
    );
    Widget headed(Widget state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        Expanded(child: state),
      ],
    );
    return list.when(
      skipLoadingOnRefresh: true,
      loading: () => _RowsSkeleton(header: header),
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
      data: (List<FileEntry> entries) => EntranceScope(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: <Widget>[
            SliverToBoxAdapter(child: header),
            CupertinoSliverRefreshControl(
              onRefresh: () => ref.refresh(folderProvider(dir).future),
            ),
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
            else
              SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (BuildContext context, int i) {
                  final FileEntry e = entries[i];
                  final Widget row = InsetGroupItem(
                    first: i == 0,
                    last: i == entries.length - 1,
                    child: FileRow(
                      key: ValueKey<String>(e.path),
                      entry: e,
                      onTap: () => openEntry(context, ref, e, entries),
                      onMore: () => showEntryActions(context, ref, e),
                      onDelete: () => deleteEntry(context, ref, e),
                    ),
                  );
                  return animateIn ? SlideUpIn(index: i, child: row) : row;
                },
              ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        ),
      ),
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton({required this.header});
  final Widget header;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        header,
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
