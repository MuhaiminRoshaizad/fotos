import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../core/format/formatters.dart';
import '../../../core/media/media_actions.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/toast.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Possible duplicates')),
      body: items.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Couldn\'t load the list',
          message: 'Try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(reviewsProvider),
        ),
        data: (List<ReviewItem> list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Nothing left to check',
                message: 'Every possible duplicate has been decided.',
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
                ),
                itemCount: list.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.lg),
                itemBuilder: (BuildContext context, int i) =>
                    _ReviewCard(item: list[i]),
              ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.item});
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
      final Set<String> gone = await ref.read(mediaActionsProvider).trash(
        context,
        <AssetEntity>[phone],
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
                    if (phone != null) ...<Widget>[
                      Expanded(child: _PhoneSide(asset: phone)),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(child: _TakeoutSide(item: item)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_busy)
                  const LinearProgressIndicator()
                else if (phone == null)
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
          if (size.hasData) Fmt.size(size.data!),
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
          ? const ColoredBox(
              color: Colors.black,
              child: Icon(Icons.movie_outlined, color: Colors.white, size: 40),
            )
          : Image.file(File(item.path), fit: BoxFit.cover, cacheWidth: 384),
      lines: <String>[
        if (item.taken != null)
          '${Fmt.date(item.taken!)} ${Fmt.time(item.taken!)}',
        Fmt.size(item.size),
      ],
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
