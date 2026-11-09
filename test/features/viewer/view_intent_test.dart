import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/viewer/presentation/view_intent_handler.dart';

void main() {
  test('reads the MediaStore id from content://media addresses only', () {
    expect(mediaStoreId('content://media/external/images/media/1234'), '1234');
    expect(
      mediaStoreId('content://media/external_primary/video/media/77'),
      '77',
    );
    expect(
      mediaStoreId('content://com.other.app.provider/files/a.jpg'),
      isNull,
    );
    expect(mediaStoreId('file:///storage/emulated/0/DCIM/a.jpg'), isNull);
    expect(mediaStoreId('content://media/external/images/media'), isNull);
  });
}
