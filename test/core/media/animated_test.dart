import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/animated.dart';
import 'package:fotos/features/viewer/presentation/strip_viewer.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

AssetEntity _picture(String title, {String? mime, int type = 1}) => AssetEntity(
  id: title,
  typeInt: type,
  width: 1000,
  height: 1400,
  title: title,
  mimeType: mime,
);

void main() {
  test('GIF and WebP pages may move; other pictures and videos do not', () {
    expect(mayAnimate(_picture('07.gif', mime: 'image/gif')), isTrue);
    expect(mayAnimate(_picture('08.webp', mime: 'image/webp')), isTrue);
    // Known by name when Android gives no type.
    expect(mayAnimate(_picture('09.GIF')), isTrue);
    expect(mayAnimate(_picture('01.jpg', mime: 'image/jpeg')), isFalse);
    expect(mayAnimate(_picture('clip.webp', type: 2)), isFalse);
  });

  test('a strip shows a moving page from its original file, a still one '
      'from a preview', () {
    final AssetEntityImageProvider moving =
        StripPage.asset(_picture('07.gif', mime: 'image/gif')).image(1080)
            as AssetEntityImageProvider;
    final AssetEntityImageProvider still =
        StripPage.asset(_picture('01.jpg', mime: 'image/jpeg')).image(1080)
            as AssetEntityImageProvider;
    expect(moving.isOriginal, isTrue);
    expect(still.isOriginal, isFalse);
  });
}
