import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/album_id.dart';

void main() {
  test('matches the album ids MediaStore gave on the phone', () {
    expect(albumIdOf('/storage/emulated/0/DCIM/Camera'), '-1739773001');
    expect(
      albumIdOf(
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/'
        'WhatsApp Video',
      ),
      '-1432612566',
    );
  });

  test('ignores letter case, as shared storage does', () {
    expect(
      albumIdOf('/storage/emulated/0/dcim/CAMERA'),
      albumIdOf('/storage/emulated/0/DCIM/Camera'),
    );
  });
}
