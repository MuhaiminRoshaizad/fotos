import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_flight.dart';

void main() {
  const Size landscape = Size(4000, 3000);

  test('at the tile the image covers the square frame', () {
    final Size s = flightImageSize(landscape, const Size(120, 120), 0);

    expect(s.height, 120);
    expect(s.width, 160);
  });

  test('at the viewer the whole image fits in the frame', () {
    final Size s = flightImageSize(landscape, const Size(400, 800), 1);

    expect(s.width, 400);
    expect(s.height, 300);
  });

  test('the image keeps its proportions all the way', () {
    for (final double t in <double>[0, 0.25, 0.5, 0.75, 1]) {
      final Size s = flightImageSize(landscape, const Size(300, 500), t);
      expect(s.aspectRatio, closeTo(landscape.aspectRatio, 1e-9));
    }
  });
}
