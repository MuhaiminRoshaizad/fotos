import 'dart:io';

import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/format/formatters.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/toast.dart';
import '../../albums/presentation/albums_providers.dart';
import '../../files/presentation/files_providers.dart';
import '../data/takeout_repository.dart';
import '../../../core/widgets/bottom_bar_space.dart';

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

/// Where the import starts: the items waiting for review, the ZIPs ready to
/// import, and how it works.
class TakeoutHomeScreen extends ConsumerWidget {
  const TakeoutHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<bool> access = ref.watch(filesAccessProvider);
    final int reviews = ref.watch(reviewsProvider).value?.length ?? 0;
    return LargeTitleScaffold(
      title: 'Takeout',
      subtitle: 'Import from Google Takeout',
      grouped: true,
      leading: const BackBarButton(label: 'Albums'),
      body: (BuildContext context, Widget header) => switch (access) {
        AsyncData<bool>(value: false) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            Expanded(
              child: EmptyState(
                icon: CupertinoIcons.folder_open,
                title: 'fotos needs to see your Download folder',
                message:
                    'The Takeout ZIPs sit in Download. Turn on All files '
                    'access for fotos, then come back.',
                actionLabel: 'Open settings',
                onAction: () => ref
                    .read(nativeChannelProvider)
                    .openAllFilesAccessSettings(),
              ),
            ),
          ],
        ),
        AsyncData<bool>(value: true) => _Body(reviews: reviews, header: header),
        _ => Align(alignment: Alignment.topCenter, child: header),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.reviews, required this.header});
  final int reviews;
  final Widget header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<File>> zips = ref.watch(_takeoutZipsProvider);
    return EntranceScope(
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: <Widget>[
          SliverToBoxAdapter(child: header),
          CupertinoSliverRefreshControl(
            onRefresh: () => ref.refresh(_takeoutZipsProvider.future),
          ),
          SliverList.list(
            children: staggered(<Widget>[
              if (reviews > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: InsetGroup(
                    children: <Widget>[
                      GroupRow(
                        leading: const Icon(CupertinoIcons.square_split_1x2),
                        title:
                            '${Fmt.count(reviews, 'possible duplicate')} to check',
                        subtitle: 'Decide which copy to keep.',
                        onTap: () => context.push('/takeout/review'),
                      ),
                    ],
                  ),
                ),
              InsetGroup(
                header: 'In Download',
                children: zips.when(
                  // The group keeps one row's height while Download is read,
                  // so the steps below don't jump when the list arrives.
                  loading: () => const <Widget>[SizedBox(height: 56)],
                  error: (_, _) => const <Widget>[
                    GroupRow(
                      leading: Icon(CupertinoIcons.exclamationmark_circle),
                      title: 'Download couldn\'t be read.',
                      subtitle: 'Pull down to try again.',
                    ),
                  ],
                  data: (List<File> list) => list.isEmpty
                      ? const <Widget>[
                          GroupRow(
                            leading: Icon(CupertinoIcons.archivebox),
                            title: 'No Takeout ZIPs yet',
                            subtitle: 'Files named takeout-….zip appear here.',
                          ),
                        ]
                      : <Widget>[
                          for (final File f in list)
                            GroupRow(
                              leading: const Icon(CupertinoIcons.archivebox),
                              title: p.basename(f.path),
                              subtitle: Fmt.size(f.lengthSync()),
                              onTap: () => context.push(
                                Uri(
                                  path: '/takeout/import',
                                  queryParameters: <String, String>{
                                    'path': f.path,
                                  },
                                ).toString(),
                              ),
                            ),
                        ],
                ),
              ),
              const InsetGroup(
                header: 'Dates',
                footer:
                    'An export comes in several ZIPs, and a photo\'s date is '
                    'often in a different one. Dates are filled in as each ZIP '
                    'is imported; this does it now from what is already here.',
                children: <Widget>[_RepairDatesRow()],
              ),
              const InsetGroup(
                header: 'How it works',
                footer:
                    'Nothing is deleted from Google. You decide that yourself, '
                    'once everything is here and checked.',
                children: <Widget>[
                  _Step(
                    n: 1,
                    text:
                        'Download each Takeout part to the phone\'s Download '
                        'folder, one at a time. The phone needs room for the '
                        'ZIP and its photos together.',
                  ),
                  _Step(
                    n: 2,
                    text:
                        'Import it. Photos already on the phone are skipped; '
                        'possible duplicates wait for you to check.',
                  ),
                  _Step(
                    n: 3,
                    text:
                        'Delete the ZIP afterwards to free the space, and keep '
                        'a copy on your PC as a backup.',
                  ),
                ],
              ),
              SizedBox(height: bottomClearance(context)),
            ]),
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 26,
            child: Text(
              '$n',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dates the imported photos Android left undated, and says how many.
class _RepairDatesRow extends ConsumerStatefulWidget {
  const _RepairDatesRow();

  @override
  ConsumerState<_RepairDatesRow> createState() => _RepairDatesRowState();
}

class _RepairDatesRowState extends ConsumerState<_RepairDatesRow> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final ({int fixed, int left}) r = await ref
          .read(takeoutRepositoryProvider)
          .repairDates();
      ref.invalidate(libraryProvider);
      ref.invalidate(albumsProvider);
      if (!mounted) return;
      final String without = r.left == 0
          ? ''
          : ' ${Fmt.count(r.left, 'item')} have no date anywhere.';
      showToast(
        context,
        r.fixed == 0 && r.left == 0
            ? 'Every imported item already has its date'
            : 'Dated ${Fmt.count(r.fixed, 'item')}.$without',
      );
    } on Exception {
      if (mounted) showToast(context, 'Couldn\'t fix the dates', failed: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => GroupRow(
    leading: const Icon(CupertinoIcons.calendar),
    title: 'Fix dates on imported photos',
    subtitle: _busy ? 'Working…' : 'For imports showing today\'s date.',
    chevron: false,
    onTap: _busy ? null : _run,
  );
}
