import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/floating_nav.dart';

void main() {
  test('the indicator sits under each tab at full width', () {
    expect(indicatorSpan(0, 4), (8.0, 56.0));
    expect(indicatorSpan(2, 4), (152.0, 56.0));
  });

  test('overshoot past either end squashes it, at most by a third', () {
    final (double l0, double w0) = indicatorSpan(-0.1, 4);
    expect(l0, 8);
    expect(w0, closeTo(56 - 7.2, 0.001));
    final (double l3, double w3) = indicatorSpan(3.5, 4);
    expect(w3, closeTo(56 * 2 / 3, 0.001));
    // It stays pinned to the right end of the last tab.
    expect(l3 + w3, 3 * 72 + 8 + 56);
  });
}
