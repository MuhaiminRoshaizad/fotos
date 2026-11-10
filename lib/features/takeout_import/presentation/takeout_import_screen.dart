import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/platform/native_channel.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/toast.dart';
import '../../albums/presentation/albums_providers.dart';
import '../../files/presentation/files_providers.dart';
import '../data/takeout_repository.dart';
import '../domain/takeout_models.dart';

enum _Stage { ready, running, finished, failed }

/// Imports one Takeout ZIP: what is in it, a live count while it runs with
/// the screen kept awake, then the summary and the next steps.
class TakeoutImportScreen extends ConsumerStatefulWidget {
  const TakeoutImportScreen({super.key, required this.path});
  final String path;

  @override
  ConsumerState<TakeoutImportScreen> createState() =>
      _TakeoutImportScreenState();
}

class _TakeoutImportScreenState extends ConsumerState<TakeoutImportScreen> {
  _Stage _stage = _Stage.ready;
  ZipInfo? _info;
  StorageStats? _space;
  TakeoutCounts _counts = const TakeoutCounts();
  String? _error;
  StreamSubscription<TakeoutCounts>? _sub;

  // Kept from initState: ref can't be used once the widget is disposing.
  late final NativeChannel _native = ref.read(nativeChannelProvider);

  @override
  void initState() {
    super.initState();
    _native;
    _inspect();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _native.keepScreenOn(false);
    super.dispose();
  }

  Future<void> _inspect() async {
    final NativeChannel native = ref.read(nativeChannelProvider);
    try {
      final ZipInfo info = await native.zipInfo(widget.path);
      final StorageStats space = await native.storage();
      if (mounted) {
        setState(() {
          _info = info;
          _space = space;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error =
              'This ZIP can\'t be read. It may be damaged or still downloading.';
        });
      }
    }
  }

  Future<void> _start() async {
    final TakeoutRepository repo = ref.read(takeoutRepositoryProvider);
    final NativeChannel native = ref.read(nativeChannelProvider);
    setState(() => _stage = _Stage.running);
    _sub = repo.progress().listen((TakeoutCounts c) {
      if (mounted) setState(() => _counts = c);
    });
    await native.keepScreenOn(true);
    try {
      final TakeoutCounts result = await repo.run(widget.path);
      AppHaptics.success();
      if (mounted) {
        setState(() {
          _counts = result;
          _stage = _Stage.finished;
        });
      }
    } on NotEnoughSpaceException catch (e) {
      AppHaptics.error();
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error =
              'Not enough space. This import needs ${Fmt.size(e.needed)} free. '
              'Nothing was written.';
        });
      }
    } on Exception {
      AppHaptics.error();
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error =
              'The import stopped. Start it again and it carries on '
              'from where it stopped.';
        });
      }
    } finally {
      await _sub?.cancel();
      await native.keepScreenOn(false);
      if (mounted) {
        ref.invalidate(libraryProvider);
        ref.invalidate(albumsProvider);
        ref.invalidate(reviewsProvider);
      }
    }
  }

  Future<void> _cancel() async {
    final bool ok = await confirmAction(
      context,
      title: 'Stop the import?',
      message:
          'What is already imported stays. Starting again later carries on '
          'from where it stopped.',
      confirmLabel: 'Stop',
    );
    if (ok) await ref.read(takeoutRepositoryProvider).cancel();
  }

  Future<void> _deleteZip() async {
    final bool ok = await confirmAction(
      context,
      title: 'Delete ${p.basename(widget.path)}?',
      message:
          'This frees ${Fmt.size(File(widget.path).lengthSync())}. Keep a '
          'copy on your PC first if you want a backup. This can\'t be undone.',
      confirmLabel: 'Delete ZIP',
    );
    if (!ok) return;
    await File(widget.path).delete();
    ref.invalidate(folderProvider);
    if (!mounted) return;
    showToast(context, 'Deleted ${p.basename(widget.path)}');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage != _Stage.running,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _cancel();
      },
      child: LargeTitleScaffold(
        title: switch (_stage) {
          _Stage.ready || _Stage.failed => 'Import',
          _Stage.running => 'Importing',
          _Stage.finished =>
            _counts.cancelled ? 'Import stopped' : 'Import finished',
        },
        subtitle: p.basename(widget.path),
        grouped: true,
        leading: const BackBarButton(label: 'Takeout'),
        body: (BuildContext context, Widget header) => switch (_stage) {
          _Stage.ready => _ready(header),
          _Stage.running => _running(header),
          _Stage.finished => _finished(header),
          _Stage.failed => _headed(
            header,
            EmptyState(
              icon: CupertinoIcons.exclamationmark_circle,
              title: 'Import didn\'t finish',
              message: _error ?? '',
              actionLabel: 'Try again',
              onAction: () {
                setState(() {
                  _stage = _Stage.ready;
                  _error = null;
                });
                _inspect();
              },
            ),
          ),
        },
      ),
    );
  }

  Widget _headed(Widget header, Widget state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      header,
      Expanded(child: state),
    ],
  );

  /// The page as a list under [header], ending clear of the system bar.
  Widget _page(Widget header, List<Widget> children) => ListView(
    padding: EdgeInsets.only(
      bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
    ),
    children: <Widget>[
      header,
      const SizedBox(height: AppSpacing.sm),
      ...children,
    ],
  );

  Widget _button(Widget button) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      0,
    ),
    child: button,
  );

  Widget _ready(Widget header) {
    final ZipInfo? info = _info;
    final StorageStats? space = _space;
    if (info == null || space == null) {
      return Align(alignment: Alignment.topCenter, child: header);
    }
    if (!info.takeout) {
      return _headed(
        header,
        const EmptyState(
          icon: CupertinoIcons.archivebox,
          title: 'This isn\'t a Google Photos Takeout',
          message:
              'It has no Takeout folder. Open it in Files to extract it '
              'instead.',
        ),
      );
    }
    final bool roomy = space.free > info.bytes;
    return _page(header, <Widget>[
      InsetGroup(
        footer: roomy
            ? 'Photos and videos go to Pictures/Takeout and Movies/Takeout, '
                  'by year, with their original dates. Locked Folder items '
                  'are skipped.'
            : 'There isn\'t enough room. Free up '
                  '${Fmt.size(info.bytes - space.free)} and try again.',
        children: <Widget>[
          GroupRow(title: 'Files inside', value: '${info.files}'),
          GroupRow(
            title: 'Size once imported',
            value: 'Up to ${Fmt.size(info.bytes)}',
          ),
          GroupRow(title: 'Free on the phone', value: Fmt.size(space.free)),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _button(
        FilledButton(
          onPressed: roomy ? _start : null,
          child: const Text('Start import'),
        ),
      ),
    ]);
  }

  Widget _running(Widget header) {
    final TakeoutCounts c = _counts;
    final ColorScheme cs = Theme.of(context).colorScheme;
    return _page(header, <Widget>[
      InsetGroup(
        footer: 'Keep fotos open. The screen stays on until this finishes.',
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  c.total == 0
                      ? 'Reading the archive…'
                      : '${c.done} of ${c.total}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: LinearProgressIndicator(
                    value: c.total == 0 ? null : c.fraction,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  c.current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      _Counts(c),
      const SizedBox(height: AppSpacing.md),
      _button(OutlinedButton(onPressed: _cancel, child: const Text('Stop'))),
    ]);
  }

  Widget _finished(Widget header) {
    final TakeoutCounts c = _counts;
    return _page(header, <Widget>[
      _Counts(c),
      const SizedBox(height: AppSpacing.md),
      if (c.review > 0)
        _button(
          FilledButton(
            onPressed: () => context.push('/takeout/review'),
            child: Text('Review ${Fmt.count(c.review, 'possible duplicate')}'),
          ),
        ),
      if (!c.cancelled)
        _button(
          OutlinedButton(
            onPressed: _deleteZip,
            child: const Text('Delete this ZIP'),
          ),
        ),
      _button(
        TextButton(onPressed: () => context.pop(), child: const Text('Done')),
      ),
    ]);
  }
}

class _Counts extends StatelessWidget {
  const _Counts(this.c);
  final TakeoutCounts c;

  @override
  Widget build(BuildContext context) {
    return InsetGroup(
      children: <Widget>[
        GroupRow(title: 'Imported', value: '${c.imported}'),
        GroupRow(
          title: 'Already on the phone (skipped)',
          value: '${c.duplicates}',
        ),
        GroupRow(title: 'Possible duplicates to check', value: '${c.review}'),
        GroupRow(title: 'Locked Folder (skipped)', value: '${c.locked}'),
        if (c.failed > 0)
          GroupRow(title: 'Couldn\'t import', value: '${c.failed}'),
      ],
    );
  }
}
