import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/format/formatters.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../albums/presentation/albums_providers.dart';
import '../../files/presentation/files_providers.dart';
import '../data/takeout_repository.dart';

/// Takeout ZIPs found in Download, newest first.
final _takeoutZipsProvider = FutureProvider.autoDispose<List<File>>((
  Ref ref,
) async {
  final String root = await ref.watch(storageRootProvider.future);
  final Directory download = Directory(p.join(root, 'Download'));
  if (!await download.exists()) return <File>[];
  final List<File> out = <File>[];
  await for (final FileSystemEntity e in download.list(recursive: true)) {
    final String name = p.basename(e.path).toLowerCase();
    if (e is File && name.startsWith('takeout-') && name.endsWith('.zip')) {
      out.add(e);
    }
  }
  out.sort((File a, File b) => b.path.compareTo(a.path));
  return out;
});

/// Where the import starts: how it works, the ZIPs ready to import, and the
/// items waiting for review.
class TakeoutHomeScreen extends ConsumerWidget {
  const TakeoutHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<bool> access = ref.watch(filesAccessProvider);
    final int reviews = ref.watch(reviewsProvider).value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Import from Google Takeout')),
      body: switch (access) {
        AsyncData<bool>(value: false) => EmptyState(
          icon: Icons.folder_open_outlined,
          title: 'fotos needs to see your Download folder',
          message:
              'The Takeout ZIPs sit in Download. Turn on All files access '
              'for fotos, then come back.',
          actionLabel: 'Open settings',
          onAction: () =>
              ref.read(nativeChannelProvider).openAllFilesAccessSettings(),
        ),
        AsyncData<bool>(value: true) => _Body(reviews: reviews),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.reviews});
  final int reviews;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AsyncValue<List<File>> zips = ref.watch(_takeoutZipsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(_takeoutZipsProvider.future),
      child: ListView(
        padding: EdgeInsets.only(
          bottom: AppNavMetrics.clearance(MediaQuery.paddingOf(context).bottom),
        ),
        children: <Widget>[
          if (reviews > 0)
            Card(
              margin: const EdgeInsets.all(AppSpacing.lg),
              color: cs.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.compare_outlined),
                title: Text(
                  '${Fmt.count(reviews, 'possible duplicate')} to check',
                ),
                subtitle: const Text('Decide which copy to keep.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/takeout/review'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              'How it works',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const _Step(
            n: 1,
            text:
                'Download each Takeout part to the phone\'s Download folder, '
                'one at a time. The phone needs room for the ZIP and its '
                'photos together.',
          ),
          const _Step(
            n: 2,
            text:
                'Import it. Photos already on the phone are skipped; possible '
                'duplicates wait for you to check.',
          ),
          const _Step(
            n: 3,
            text:
                'Delete the ZIP afterwards to free the space, and keep a copy '
                'on your PC as a backup.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              'In Download',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...zips.when(
            loading: () => const <Widget>[SizedBox.shrink()],
            error: (_, _) => const <Widget>[
              ListTile(title: Text('Download couldn\'t be read.')),
            ],
            data: (List<File> list) => list.isEmpty
                ? const <Widget>[
                    ListTile(
                      leading: Icon(Icons.folder_zip_outlined),
                      title: Text('No Takeout ZIPs yet'),
                      subtitle: Text('Files named takeout-….zip appear here.'),
                    ),
                  ]
                : <Widget>[
                    for (final File f in list)
                      ListTile(
                        leading: const Icon(Icons.folder_zip_outlined),
                        title: Text(
                          p.basename(f.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(Fmt.size(f.lengthSync())),
                        trailing: FilledButton.tonal(
                          onPressed: () => context.push(
                            Uri(
                              path: '/takeout/import',
                              queryParameters: <String, String>{'path': f.path},
                            ).toString(),
                          ),
                          child: const Text('Import'),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: cs.primaryContainer,
        child: Text(
          '$n',
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(text),
    );
  }
}
