import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/grid_geometry.dart';

void main() {
  // 4 columns over 406 px with 2 px gaps: tiles are exactly 100 px.
  final GridGeometry geo = GridGeometry(
    width: 406,
    columns: 4,
    groupSizes: <int>[6, 4, 1],
    headerExtent: 44,
    spacing: 2,
  );

  test('tile size and group positions', () {
    expect(geo.tile, 100);
    expect(geo.groupTop(0), 0);
    // group 0: header 44 + 2 rows (200) + 1 gap (2) = 246
    expect(geo.groupTop(1), 246);
    // group 1: 44 + 100 = 144
    expect(geo.groupTop(2), 390);
    expect(geo.contentHeight, 390 + 144);
    expect(geo.itemCount, 11);
  });

  test('item and group at an offset', () {
    expect(geo.groupAt(0), 0);
    expect(geo.groupAt(245), 0);
    expect(geo.groupAt(246), 1);
    expect(geo.itemAt(0), 0);
    expect(geo.itemAt(44 + 102), 4); // second row of group 0
    expect(geo.itemAt(400), 10);
  });

  test('offsetOf puts the row of an item at the top', () {
    expect(geo.offsetOf(0), 0);
    expect(geo.offsetOf(4), 44 + 102);
    expect(geo.offsetOf(6), 246);
    for (final int i in <int>[0, 4, 6, 10]) {
      expect(geo.itemAt(geo.offsetOf(i)), i);
    }
  });
}
