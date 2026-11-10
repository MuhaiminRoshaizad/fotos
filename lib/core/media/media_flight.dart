import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

/// How large the whole image is drawn inside the flying frame [frame], [t]
/// of the way from a grid tile (0) to the viewer (1).
///
/// A tile shows the image cropped to fill its square; the viewer shows all of
/// it. Sizing the image from "covers the frame" to "fits in the frame" as the
/// frame grows makes the crop open up, so the flight starts exactly as the
/// tile looks and ends exactly as the viewer looks.
Size flightImageSize(Size image, Size frame, double t) {
  final double w = frame.width / image.width;
  final double h = frame.height / image.height;
  final double scale = math.max(w, h) + (math.min(w, h) - math.max(w, h)) * t;
  return image * scale;
}

/// The straight path of a photo between its tile and the viewer. Material's
/// default is an arc, which reads as a toss; iOS moves it directly.
Tween<Rect?> mediaFlightTween(Rect? begin, Rect? end) =>
    RectTween(begin: begin, end: end);

/// What flies between a grid tile and the viewer for [asset]: the tile's own
/// thumbnail, uncropping on the way up and cropping again on the way back.
/// Set on both ends of the flight.
HeroFlightShuttleBuilder mediaFlightShuttle(AssetEntity asset) {
  return (
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // The tile is where a push starts and where a pop ends.
    final Hero tile =
        (direction == HeroFlightDirection.push
                    ? fromHeroContext
                    : toHeroContext)
                .widget
            as Hero;
    final Size image = Size(
      asset.orientatedWidth.toDouble(),
      asset.orientatedHeight.toDouble(),
    );
    if (image.isEmpty) return tile.child;
    return AnimatedBuilder(
      animation: animation,
      child: tile.child,
      builder: (BuildContext context, Widget? child) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final Size s = flightImageSize(image, box.biggest, animation.value);
          return ClipRect(
            child: OverflowBox(
              minWidth: s.width,
              maxWidth: s.width,
              minHeight: s.height,
              maxHeight: s.height,
              child: child,
            ),
          );
        },
      ),
    );
  };
}
