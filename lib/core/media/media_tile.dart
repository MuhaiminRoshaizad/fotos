import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../format/formatters.dart';
import '../theme/app_tokens.dart';
import 'media_flight.dart';

/// Thumbnail sizes are bucketed so the same decode serves every grid level.
int thumbnailPixels(double logicalWidth, double devicePixelRatio) {
  final double px = logicalWidth * devicePixelRatio;
  if (px <= 160) return 160;
  if (px <= 256) return 256;
  return 384;
}

/// One square in a media grid: the thumbnail, a length badge on videos, a
/// heart on favourites and, while selecting, a check circle.
class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.asset,
    required this.heroTag,
    this.selecting = false,
    this.selected = false,
  });

  final AssetEntity asset;
  final String heroTag;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool video = asset.type == AssetType.video;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final int px = thumbnailPixels(
          c.maxWidth,
          MediaQuery.devicePixelRatioOf(context),
        );
        final Widget image = Image(
          image: AssetEntityImageProvider(
            asset,
            isOriginal: false,
            thumbnailSize: ThumbnailSize.square(px),
          ),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (_, Widget child, int? frame, bool sync) {
            if (sync) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: AppMotion.short,
              child: child,
            );
          },
          errorBuilder: (_, _, _) => Center(
            child: Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: AppIconSize.dense,
              color: cs.onSurfaceVariant,
            ),
          ),
        );
        return Semantics(
          button: true,
          selected: selecting ? selected : null,
          label:
              '${video ? 'Video' : 'Photo'}, ${Fmt.date(asset.createDateTime)} '
              '${Fmt.time(asset.createDateTime)}'
              '${asset.isFavorite ? ', favourite' : ''}',
          excludeSemantics: true,
          child: ColoredBox(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                AnimatedScale(
                  scale: selected ? 0.84 : 1,
                  duration: AppMotion.short,
                  curve: AppMotion.emphasized,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      selected ? AppRadii.md : 0,
                    ),
                    child: Hero(
                      tag: heroTag,
                      createRectTween: mediaFlightTween,
                      flightShuttleBuilder: mediaFlightShuttle(asset),
                      child: image,
                    ),
                  ),
                ),
                if (video)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: _Badge(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            CupertinoIcons.play_fill,
                            size: 14,
                            color: Colors.white,
                          ),
                          Text(
                            Fmt.duration(asset.videoDuration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFeatures: <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (asset.isFavorite)
                  const Positioned(
                    left: 4,
                    bottom: 4,
                    child: Icon(
                      CupertinoIcons.heart_fill,
                      size: AppIconSize.badge,
                      color: Colors.white,
                      shadows: <Shadow>[
                        Shadow(blurRadius: 3, color: Colors.black54),
                      ],
                    ),
                  ),
                if (selecting)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _Check(selected: selected),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(2, 1, 6, 1),
      child: child,
    ),
  );
}

class _Check extends StatelessWidget {
  const _Check({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.short,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? cs.primary : Colors.black.withValues(alpha: 0.18),
        border: Border.all(
          color: selected ? cs.surface : Colors.white,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(CupertinoIcons.checkmark, size: 14, color: cs.onPrimary)
          : null,
    );
  }
}
