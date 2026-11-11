import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/motion_name.dart';

void main() {
  test('Pixel Motion Photo names are recognised', () {
    expect(looksLikeMotionPhoto('PXL_20251206_045634783.MP.jpg'), isTrue);
    expect(looksLikeMotionPhoto('PXL_20251206_045634783.MP.JPG'), isTrue);
    expect(looksLikeMotionPhoto('MVIMG_20190817_123456.jpg'), isTrue);
  });

  test('ordinary photos and videos are not', () {
    expect(looksLikeMotionPhoto('PXL_20251206_045634783.jpg'), isFalse);
    expect(
      looksLikeMotionPhoto('PXL_20251206_045634783.PORTRAIT.jpg'),
      isFalse,
    );
    expect(looksLikeMotionPhoto('PXL_20251206_045634783.MP'), isFalse);
    expect(looksLikeMotionPhoto('IMG-20180720-WA0010.jpg'), isFalse);
    expect(looksLikeMotionPhoto(null), isFalse);
  });
}
