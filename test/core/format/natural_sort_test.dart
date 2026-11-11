import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/format/natural_sort.dart';

/// Sorts a copy of [names] with [naturalCompare] so each test reads as the
/// order a person would expect, not a pile of pairwise comparisons.
List<String> sorted(List<String> names) =>
    List<String>.of(names)..sort(naturalCompare);

void main() {
  test('comic pages keep their number order, not their text order', () {
    expect(
      sorted(<String>['1.jpg', '10.jpg', '2.jpg', '20.jpg', '3.jpg', '11.jpg']),
      <String>['1.jpg', '2.jpg', '3.jpg', '10.jpg', '11.jpg', '20.jpg'],
    );
  });

  test('a number anywhere in the name is read as a number', () {
    expect(
      sorted(<String>['page 10', 'page 2', 'page 1']),
      <String>['page 1', 'page 2', 'page 10'],
    );
  });

  test('leading zeros do not change the value but keep a stable order', () {
    // 001, 01 and 1 are the same page; the shorter spelling sorts first.
    expect(sorted(<String>['01', '1', '001']), <String>['1', '01', '001']);
    expect(
      sorted(<String>['img_009', 'img_010', 'img_008']),
      <String>['img_008', 'img_009', 'img_010'],
    );
  });

  test('digit runs compare by value past the 64-bit range', () {
    expect(naturalCompare('9999999999999999999', '10000000000000000000'), -1);
  });

  test('letters compare ignoring case', () {
    expect(
      sorted(<String>['beach.mp4', 'Alley.mp4', 'cake.mp4']),
      <String>['Alley.mp4', 'beach.mp4', 'cake.mp4'],
    );
  });

  test('a shorter name sorts before the one it prefixes', () {
    expect(sorted(<String>['page', 'page 2']), <String>['page', 'page 2']);
  });

  test('names equal but for case keep a deterministic order', () {
    expect(naturalCompare('A', 'a'), lessThan(0));
    expect(naturalCompare('a', 'A'), greaterThan(0));
    expect(naturalCompare('file 1', 'file 1'), 0);
  });
}
