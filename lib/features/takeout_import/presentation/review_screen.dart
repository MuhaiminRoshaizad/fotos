import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/media_actions.dart';
import '../../../core/media/media_providers.dart';
import '../../albums/presentation/albums_providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/toast.dart';
import '../../files/domain/file_entry.dart';
import '../../files/presentation/file_media_viewer.dart';
import '../data/takeout_repository.dart';
import '../domain/takeout_models.dart';

/// Each possible duplicate side by side: the phone's copy and the Takeout
/// copy. Removing the phone's copy goes through Android's trash, so it can
/// still be undone from Recently deleted.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ReviewItem>> items = ref.watch(reviewsProvider);
    return LargeTitleScaffold(
      title: 'Duplicates',
      subtitle: items.hasValue
          ? '${Fmt.count(items.value!.length, 'possible duplicate')} to check'
          : '',
      grouped: true,
      leading: const BackBarButton(label: 'Takeout'),
      body: (BuildContext context, Widget header) {
        Widget headed(Widget state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            Expanded(child: state),
          ],
        );
        return items.when(
          loading: () => headed(const _ReviewSkeleton()),
          error: (_, _) => headed(
            EmptyState(
              icon: CupertinoIcons.exclamationmark_circle,
              title: 'Couldn\'t load the list',
              message: 'Try again.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(reviewsProvider),
            ),
          ),
          data: (List<ReviewItem> list) => list.isEmpty
              ? headed(
                  const EmptyState(
                    icon: CupertinoIcons.checkmark_circle,
                    title: 'Nothing left to check',
                    message: 'Every possible duplicate has been decided.',
                  ),
                )
              : EntranceScope(
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      bottom:
                          MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
                    ),
                    itemCount: list.length + 1,
                    itemBuilder: (BuildContext context, int i) => i == 0
                        ? header
                        : SlideUpIn(
                            index: i - 1,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                AppSpacing.sm,
                                AppSpacing.lg,
                                AppSpacing.sm,
                              ),
                              child: _ReviewCard(
                                key: ValueKey<String>(list[i - 1].id),
                                item: list[i - 1],
                              ),
                            ),
                          ),
                  ),
                ),
        );
      },
    );
  }
}

/// Two cards' worth of placeholder in the shape of a real review card:
/// name, reason, the square picture, a size line and the two buttons.
class _ReviewSkeleton extends StatelessWidget {
  const _ReviewSkeleton();

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Skeletonizer(
      enabled: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: <Widget>[
          for (int i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'PXL_20251206_045644648.MP',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Why this item was set aside for you to decide.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const Text('2.2 MB', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({super.key, required this.item});
  final ReviewItem item;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  late final Future<AssetEntity?> _phone = widget.item.phoneId == null
      ? Future<AssetEntity?>.value()
      : AssetEntity.fromId(widget.item.phoneId!);
  bool _busy = false;

  Future<void> _decide({
    required bool keepTakeout,
    required bool removePhone,
  }) async {
    setState(() => _busy = true);
    final ReviewItem item = widget.item;
    final AssetEntity? phone = await _phone;
    if (removePhone && phone != null) {
      if (!mounted) return;
      // "Keep Takeout's" on a card showing both copies is the question
      // already answered.
      final Set<String> gone = await ref.read(mediaActionsProvider).trash(
        context,
        <AssetEntity>[phone],
        confirm: false,
      );
      if (gone.isEmpty) {
        // The user refused Android's confirmation: change nothing.
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    await ref
        .read(takeoutRepositoryProvider)
        .resolve(item, keepTakeout: keepTakeout);
    ref.invalidate(reviewsProvider);
    ref.invalidate(libraryProvider);
    ref.invalidate(albumsProvider);
    if (mounted && !removePhone) {
      showToast(context, keepTakeout ? 'Kept both' : 'Kept the phone\'s copy');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReviewItem item = widget.item;
    final ColorScheme cs = Theme.of(context).colorScheme;
    // Laid out from what the item says, not from the lookup's result: a
    // card that changed height once its phone copy arrived made the list's
    // length flicker at the bottom, and the bounce chased it without end.
    final bool paired = item.phoneId != null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: FutureBuilder<AssetEntity?>(
          future: _phone,
          builder: (BuildContext context, AsyncSnapshot<AssetEntity?> s) {
            final AssetEntity? phone = s.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  item.reason.explanation,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (paired) ...<Widget>[
                      Expanded(
                        child: phone != null
                            ? _PhoneSide(asset: phone)
                            : _Side(
                                label: 'On the phone',
                                image: ColoredBox(
                                  color: cs.surfaceContainerHigh,
                                ),
                                lines: <String>[
                                  s.connectionState == ConnectionState.done
                                      ? 'No longer on the phone'
                                      : '',
                                  '',
                                  '',
                                ],
                              ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(child: _TakeoutSide(item: item)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_busy)
                  const LinearProgressIndicator()
                else if (!paired)
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              _decide(keepTakeout: false, removePhone: false),
                          child: const Text('Discard'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              _decide(keepTakeout: true, removePhone: false),
                          child: const Text('Import it'),
                        ),
                      ),
                    ],
                  )
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    alignment: WrapAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: () =>
                            _decide(keepTakeout: true, removePhone: false),
                        child: const Text('Keep both'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _decide(keepTakeout: false, removePhone: false),
                        child: const Text('Keep phone\'s'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            _decide(keepTakeout: true, removePhone: true),
                        child: const Text('Keep Takeout\'s'),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PhoneSide extends StatelessWidget {
  const _PhoneSide({required this.asset});
  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: asset.fileSize,
      builder: (BuildContext context, AsyncSnapshot<int> size) => _Side(
        label: 'On the phone',
        image: Image(
          image: AssetEntityImageProvider(
            asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(384),
          ),
          fit: BoxFit.cover,
        ),
        lines: <String>[
          '${Fmt.date(asset.createDateTime)} ${Fmt.time(asset.createDateTime)}',
          size.hasData ? Fmt.size(size.data!) : '',
          '${asset.orientatedWidth} × ${asset.orientatedHeight}',
        ],
      ),
    );
  }
}

class _TakeoutSide extends StatelessWidget {
  const _TakeoutSide({required this.item});
  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    return _Side(
      label: 'From Takeout',
      image: item.video
          ? _StagedVideo(item: item)
          : Image.file(File(item.path), fit: BoxFit.cover, cacheWidth: 384),
      lines: <String>[
        if (item.taken != null)
          '${Fmt.date(item.taken!)} ${Fmt.time(item.taken!)}',
        Fmt.size(item.size),
      ],
    );
  }
}

/// A frame from the staged video with a play badge; tap to watch it. The
/// box is sized by its parent, so the frame arriving moves nothing.
class _StagedVideo extends ConsumerStatefulWidget {
  const _StagedVideo({required this.item});
  final ReviewItem item;

  @override
  ConsumerState<_StagedVideo> createState() => _StagedVideoState();
}

class _StagedVideoState extends ConsumerState<_StagedVideo> {
  late final Future<Uint8List?> _frame = ref
      .read(nativeChannelProvider)
      .videoFrame(widget.item.path, 512);

  void _play() {
    final ReviewItem item = widget.item;
    openFileMedia(context, <FileEntry>[
      FileEntry(
        path: item.path,
        name: item.name,
        kind: FileKind.video,
        size: item.size,
        modified: item.taken ?? DateTime.now(),
      ),
    ], 0);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play ${widget.item.name}',
      child: GestureDetector(
        onTap: _play,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: Colors.black),
            FutureBuilder<Uint8List?>(
              future: _frame,
              builder: (BuildContext context, AsyncSnapshot<Uint8List?> s) =>
                  s.data == null
                  ? const SizedBox.shrink()
                  : Image.memory(
                      s.data!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Icon(
                    CupertinoIcons.play_fill,
                    color: Colors.white,
                    size: 28,
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

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.image, required this.lines});
  final String label;
  final Widget image;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: image,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final String l in lines)
          Text(
            l,
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}
