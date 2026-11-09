import 'dart:math' as math;

/// Where every group and item sits in a grouped media grid. The grid's rows
/// and headers have fixed extents, so positions are computed, not measured;
/// the scrubber and zoom anchoring both rely on this.
class GridGeometry {
  GridGeometry({
    required this.width,
    required this.columns,
    required List<int> groupSizes,
    this.headerExtent = 44,
    this.spacing = 2,
  }) : _sizes = groupSizes {
    tile = (width - spacing * (columns - 1)) / columns;
    double top = 0;
    int start = 0;
    for (final int n in _sizes) {
      _tops.add(top);
      _starts.add(start);
      top += _groupHeight(n);
      start += n;
    }
    contentHeight = top;
    itemCount = start;
  }

  final double width;
  final int columns;
  final double headerExtent;
  final double spacing;
  final List<int> _sizes;
  final List<double> _tops = <double>[];
  final List<int> _starts = <int>[];

  late final double tile;
  late final double contentHeight;
  late final int itemCount;

  int get groupCount => _sizes.length;
  double groupTop(int g) => _tops[g];
  int groupStart(int g) => _starts[g];

  int _rows(int n) => (n + columns - 1) ~/ columns;

  double _groupHeight(int n) {
    final int rows = _rows(n);
    return headerExtent + rows * tile + math.max(0, rows - 1) * spacing;
  }

  /// The group showing at scroll [offset].
  int groupAt(double offset) {
    if (_tops.isEmpty) return 0;
    int lo = 0, hi = _tops.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1;
      if (_tops[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The first item whose row is visible at scroll [offset].
  int itemAt(double offset) {
    if (itemCount == 0) return 0;
    final int g = groupAt(offset);
    final double inside = offset - _tops[g] - headerExtent;
    final int row = inside <= 0 ? 0 : (inside / (tile + spacing)).floor();
    final int i = _starts[g] + row * columns;
    return math.min(i, _starts[g] + _sizes[g] - 1);
  }

  /// The scroll offset that puts [item]'s row at the top, its group's heading
  /// included when the item is in the first row.
  double offsetOf(int item) {
    if (itemCount == 0) return 0;
    int g = groupCount - 1;
    while (g > 0 && _starts[g] > item) {
      g--;
    }
    final int row = (item - _starts[g]) ~/ columns;
    if (row == 0) return _tops[g];
    return _tops[g] + headerExtent + row * (tile + spacing);
  }
}
