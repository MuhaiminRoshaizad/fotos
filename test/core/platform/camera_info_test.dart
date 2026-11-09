import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/platform/native_channel.dart';

void main() {
  test('camera name does not repeat the make', () {
    expect(
      const CameraInfo(make: 'Google', model: 'Pixel 9 Pro').camera,
      'Google Pixel 9 Pro',
    );
    expect(
      const CameraInfo(make: 'Google', model: 'Google Pixel 9 Pro').camera,
      'Google Pixel 9 Pro',
    );
    expect(
      const CameraInfo(make: 'Canon', model: 'EOS R6').camera,
      'Canon EOS R6',
    );
    expect(const CameraInfo().camera, isNull);
  });

  test('settings line formats aperture, shutter, ISO and focal length', () {
    expect(
      const CameraInfo(
        fNumber: 1.7,
        exposure: 1 / 120,
        iso: 64,
        focalLength: 6.9,
      ).settings,
      'f/1.7 · 1/120 s · ISO 64 · 6.9 mm',
    );
    expect(const CameraInfo(exposure: 2).settings, '2 s');
    expect(const CameraInfo().settings, '');
  });
}
