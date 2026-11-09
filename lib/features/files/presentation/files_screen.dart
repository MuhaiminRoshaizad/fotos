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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Files',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (access.value == true && root.hasValue)
                      NewFolderButton(dir: root.value!),
                  ],
                ),
              ),
            ),
            Expanded(
              child: switch ((access, root)) {
                (
                  AsyncData<bool>(value: true),
                  AsyncData<String>(:final value),
                ) =>
                  FolderBody(dir: value, header: const _StorageCard()),
                (AsyncData<bool>(value: false), _) => EmptyState(
                  icon: Icons.folder_open_outlined,
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
                (AsyncError<bool>(), _) ||
                (_, AsyncError<String>()) => EmptyState(
                  icon: Icons.error_outline,
                  title: 'Couldn\'t open Files',
                  message: 'Android didn\'t answer. Try again.',
                  actionLabel: 'Try again',
                  onAction: () {
                    ref.invalidate(filesAccessProvider);
                    ref.invalidate(storageRootProvider);
                  },
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageCard extends ConsumerWidget {
  const _StorageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final StorageStats? s = ref.watch(storageStatsProvider).value;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: Text('Internal storage')),
              Text(
                s == null
                    ? ''
                    : '${Fmt.size(s.used)} of ${Fmt.size(s.total)} used',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: s == null ? 0 : s.used / s.total,
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class NewFolderButton extends ConsumerWidget {
  const NewFolderButton({super.key, required this.dir});
  final String dir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'New folder',
      icon: const Icon(Icons.create_new_folder_outlined),
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

/// A folder's contents with loading, empty and error states.
class FolderBody extends ConsumerWidget {
  const FolderBody({super.key, required this.dir, this.header});

  final String dir;
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FileEntry>> list = ref.watch(folderProvider(dir));
    final double bottom = AppNavMetrics.clearance(
      MediaQuery.paddingOf(context).bottom,
    );
    return list.when(
      skipLoadingOnRefresh: true,
      loading: () => _RowsSkeleton(header: header),
      error: (_, _) => EmptyState(
        icon: Icons.folder_off_outlined,
        title: 'Can\'t open ${p.basename(dir)}',
        message: p.basename(dir) == 'Android'
            ? 'Android protects app data in this folder. Other apps, fotos '
                  'included, can\'t open it.'
            : 'Android didn\'t allow reading this folder.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(folderProvider(dir)),
      ),
      data: (List<FileEntry> entries) => RefreshIndicator(
        onRefresh: () => ref.refresh(folderProvider(dir).future),
        child: entries.isEmpty
            ? ListView(
                children: <Widget>[
                  ?header,
                  const SizedBox(
                    height: 360,
                    child: EmptyState(
                      icon: Icons.folder_outlined,
                      title: 'This folder is empty',
                      message:
                          'Files you save or extract here appear in this list.',
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: EdgeInsets.only(bottom: bottom),
                itemCount: entries.length + (header == null ? 0 : 1),
                itemBuilder: (BuildContext context, int i) {
                  if (header != null && i == 0) return header!;
                  final FileEntry e = entries[i - (header == null ? 0 : 1)];
                  return FileRow(
                    entry: e,
                    onTap: () => openEntry(context, ref, e, entries),
                    onMore: () => showEntryActions(context, ref, e),
                  );
                },
              ),
      ),
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton({this.header});
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          ?header,
          for (int i = 0; i < 8; i++)
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
              ),
              title: const Text('Folder name here'),
              subtitle: const Text('09/11/2026'),
              trailing: const Icon(Icons.more_vert),
            ),
        ],
      ),
    );
  }
}
