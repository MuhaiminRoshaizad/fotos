import '../format/formatters.dart';

/// How densely the grid shows the library, from widest view to closest.
enum GridLevel {
  years(columns: 7),
  months(columns: 5),
  all(columns: 4),
  days(columns: 3);

  const GridLevel({required this.columns});
  final int columns;

  String get label => switch (this) {
    GridLevel.years => 'Years',
    GridLevel.months => 'Months',
    GridLevel.all => 'All',
    GridLevel.days => 'Days',
  };

  /// One step closer (pinch out) or further (pinch in), clamped at the ends.
  GridLevel step(int delta) {
    final int i = (index + delta).clamp(0, GridLevel.values.length - 1);
    return GridLevel.values[i];
  }
}

/// A run of items sharing one heading in the grid.
class MediaGroup<T> {
  const MediaGroup(this.label, this.items);
  final String label;
  final List<T> items;
}

/// Splits [items], already newest first, into headed groups for [level].
/// Years group by year, Days by calendar day, Months and All by month.
List<MediaGroup<T>> groupByDate<T>(
  List<T> items,
  DateTime Function(T) dateOf,
  GridLevel level,
) {
  final List<MediaGroup<T>> groups = <MediaGroup<T>>[];
  String? current;
  for (final T item in items) {
    final DateTime d = dateOf(item);
    final String label = switch (level) {
      GridLevel.years => '${d.year}',
      GridLevel.days => Fmt.dayHeading(d),
      GridLevel.months || GridLevel.all => Fmt.monthYear(d),
    };
    if (label != current) {
      groups.add(MediaGroup<T>(label, <T>[]));
      current = label;
    }
    groups.last.items.add(item);
  }
  return groups;
}
