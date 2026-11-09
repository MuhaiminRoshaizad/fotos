import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/grouping.dart';

void main() {
  final List<DateTime> dates = <DateTime>[
    DateTime(2026, 11, 9, 14, 32),
    DateTime(2026, 11, 9, 8),
    DateTime(2026, 11, 2),
    DateTime(2026, 10, 30),
    DateTime(2019, 7, 4),
  ];

  List<String> labels(GridLevel level) => groupByDate<DateTime>(
    dates,
    (DateTime d) => d,
    level,
  ).map((MediaGroup<DateTime> g) => '${g.label}:${g.items.length}').toList();

  test('months and all group by month, newest first', () {
    expect(labels(GridLevel.months), <String>[
      'November 2026:3',
      'October 2026:1',
      'July 2019:1',
    ]);
    expect(labels(GridLevel.all), labels(GridLevel.months));
  });

  test('days group by calendar day with a dd/mm/yyyy heading', () {
    expect(labels(GridLevel.days).first, 'Monday, 09/11/2026:2');
    expect(labels(GridLevel.days), hasLength(4));
  });

  test('years group by year', () {
    expect(labels(GridLevel.years), <String>['2026:4', '2019:1']);
  });

  test('step clamps at both ends', () {
    expect(GridLevel.years.step(-1), GridLevel.years);
    expect(GridLevel.days.step(1), GridLevel.days);
    expect(GridLevel.all.step(1), GridLevel.days);
    expect(GridLevel.all.step(-1), GridLevel.months);
  });

  test('wide screens add columns, phones keep the base count', () {
    expect(GridLevel.all.columnsFor(390), 4);
    expect(GridLevel.all.columnsFor(412), 4);
    expect(GridLevel.all.columnsFor(800), 8);
    expect(GridLevel.days.columnsFor(1280), 9);
    expect(GridLevel.years.columnsFor(5000), 21);
  });
}
