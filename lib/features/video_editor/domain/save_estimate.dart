import 'dart:math' as math;

/// How long a save has left, from how fast it is going now.
///
/// The encoder's progress is not steady: on the emulator a save jumped
/// from 0 to 50% in a few seconds and then took a minute per percent, so
/// the average pace since the start said 2 minutes when it was half an
/// hour. The pace is taken over the last stretch of reports instead: back
/// to the most recent report at least [window] old, or the last percent
/// when reports are further apart than that.
///
/// Each new percent sets when the save should finish; in between, [left]
/// counts down to that moment rather than growing while it waits for the
/// next report.
class SaveEstimate {
  SaveEstimate(this._elapsed);

  /// Time since the save started.
  final Duration Function() _elapsed;

  final List<({Duration at, int percent})> _reports =
      <({Duration at, int percent})>[];
  Duration? _finishAt;

  /// How far back the pace is measured.
  static const Duration window = Duration(seconds: 10);

  /// Too soon to judge before this long after the first percent.
  static const Duration _minTime = Duration(seconds: 3);

  void report(int percent) {
    final Duration now = _elapsed();
    if (percent <= 0) return;
    if (percent >= 100) {
      _finishAt = null;
      return;
    }
    _reports.add((at: now, percent: percent));
    if (now - _reports.first.at < _minTime) return;
    // The latest earlier report at least a percent behind and, if there
    // is one, at least [window] old.
    ({Duration at, int percent})? from;
    for (final ({Duration at, int percent}) r in _reports.reversed) {
      if (r.percent >= percent) continue;
      from ??= r;
      if (now - r.at >= window) {
        from = r;
        break;
      }
    }
    if (from == null) return;
    final Duration perPercent =
        (now - from.at) * (1 / (percent - from.percent));
    _finishAt = now + perPercent * (100 - percent);
    // Older reports can no longer be the start of the window.
    _reports.removeWhere((r) => now - r.at > window * 3 && r != from);
  }

  /// The time left, or null while it is too soon to say.
  Duration? get left {
    final Duration? end = _finishAt;
    if (end == null) return null;
    final Duration rest = end - _elapsed();
    return rest.isNegative ? Duration.zero : rest;
  }
}

/// [left] in words, as GNOME's guidelines put an estimate ("About 3
/// minutes left"), rounded coarser as it grows so the figure doesn't
/// flicker.
String timeLeft(Duration? left) {
  if (left == null) return 'Working out the time left';
  final int s = left.inSeconds;
  if (s < 10) return 'Almost done';
  if (s < 60) return 'About ${math.min(55, (s / 5).round() * 5)} seconds left';
  if (s < 90) return 'About a minute left';
  if (s < 3570) return 'About ${(s / 60).round()} minutes left';
  // Past an hour, to the nearest five minutes.
  final int fives = (s / 300).round();
  final int hours = fives ~/ 12;
  final int minutes = fives % 12 * 5;
  final String h = hours == 1 ? '1 hour' : '$hours hours';
  return minutes == 0 ? 'About $h left' : 'About $h $minutes minutes left';
}
