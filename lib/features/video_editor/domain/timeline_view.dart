import 'package:flutter/foundation.dart';

/// What the editor's timeline shows: the moment under the playhead in the
/// middle of the strip, and how many milliseconds each point covers.
///
/// Zoomed all the way out the whole video spans half the strip, so with
/// the playhead in the middle all of it is in view wherever the playhead
/// is; zoomed all the way in the strip spans [finestSpan], so a cut can be
/// placed to a fraction of a second even in an hour-long video.
@immutable
class TimelineView {
  const TimelineView({
    required this.duration,
    required this.centre,
    required this.msPerPoint,
  });

  /// Zoomed all the way out, at the start.
  factory TimelineView.fit(int duration, double width) => TimelineView(
    duration: duration,
    centre: 0,
    msPerPoint: coarsest(duration, width),
  );

  /// How much of the video the strip spans zoomed all the way in.
  static const int finestSpan = 10000;

  final int duration;

  /// The moment under the playhead, in ms.
  final double centre;
  final double msPerPoint;

  /// Room kept past the video's end zoomed out, so the end handle's grip,
  /// drawn just after it, stays on screen.
  static const double endRoom = 28;

  /// Zoomed all the way out: the whole video across half the strip, less
  /// [endRoom].
  static double coarsest(int duration, double width) {
    final double span = width / 2 - endRoom;
    return duration / (span <= 1 ? 1 : span);
  }

  /// Zoomed all the way in, never finer than the whole video for a video
  /// shorter than [finestSpan].
  static double finest(int duration, double width) {
    final double c = coarsest(duration, width);
    final double f = finestSpan / (width <= 0 ? 1 : width);
    return f < c ? f : c;
  }

  /// Where [ms] sits on a strip [width] points wide.
  double xOf(num ms, double width) => width / 2 + (ms - centre) / msPerPoint;

  /// The moment at [x] on a strip [width] points wide.
  int msAt(double x, double width) =>
      (centre + (x - width / 2) * msPerPoint).round();

  /// With the playhead at [ms], kept on the video.
  TimelineView at(num ms) => TimelineView(
    duration: duration,
    centre: ms.clamp(0, duration).toDouble(),
    msPerPoint: msPerPoint,
  );

  /// Zoomed to [msPerPoint] within what [width] allows, about the playhead.
  TimelineView zoomed(double msPerPoint, double width) => TimelineView(
    duration: duration,
    centre: centre,
    msPerPoint: msPerPoint.clamp(
      finest(duration, width),
      coarsest(duration, width),
    ),
  );

  bool zoomedIn(double width) => msPerPoint < coarsest(duration, width) * 0.999;

  /// The spacing of the frames along the strip: the first round step that
  /// gives each frame at least [tile] points.
  int tileStep(double tile) {
    final double want = msPerPoint * tile;
    for (final int s in _steps) {
      if (s >= want) return s;
    }
    final int hour = _steps.last;
    return ((want / hour).ceil()) * hour;
  }

  static const List<int> _steps = <int>[
    250,
    500,
    1000,
    2000,
    5000,
    10000,
    15000,
    30000,
    60000,
    120000,
    300000,
    600000,
    900000,
    1800000,
    3600000,
  ];

  @override
  bool operator ==(Object other) =>
      other is TimelineView &&
      other.duration == duration &&
      other.centre == centre &&
      other.msPerPoint == msPerPoint;

  @override
  int get hashCode => Object.hash(duration, centre, msPerPoint);
}
