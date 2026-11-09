import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/takeout_import/domain/takeout_models.dart';

void main() {
  test('counts parse from the native map, missing keys as zero', () {
    final TakeoutCounts c = TakeoutCounts.fromMap(<Object?, Object?>{
      'imported': 12,
      'duplicates': 3,
      'review': 2,
      'locked': 1,
      'done': 18,
      'total': 36,
      'current': 'IMG_0300.JPG',
    });
    expect(c.imported, 12);
    expect(c.failed, 0);
    expect(c.fraction, 0.5);
    expect(c.cancelled, isFalse);
    expect(const TakeoutCounts().fraction, 0);
  });

  test('review items parse reason, date and the phone match', () {
    final ReviewItem r = ReviewItem.fromMap(<Object?, Object?>{
      'id': 'a1',
      'path': '/x/a1-IMG_0300.JPG',
      'name': 'IMG_0300.JPG',
      'video': false,
      'size': 2048,
      'reason': 'time',
      'taken': 1569834512000,
      'phoneId': '42',
    });
    expect(r.reason, ReviewReason.time);
    expect(r.taken, DateTime.fromMillisecondsSinceEpoch(1569834512000));
    expect(r.phoneId, '42');

    final ReviewItem m = ReviewItem.fromMap(<Object?, Object?>{
      'id': 'b',
      'path': '/x/b',
      'name': 'PXL_1.MP',
      'reason': 'motion',
      'taken': null,
      'phoneId': null,
    });
    expect(m.reason, ReviewReason.motion);
    expect(m.taken, isNull);
    expect(m.phoneId, isNull);
  });
}
