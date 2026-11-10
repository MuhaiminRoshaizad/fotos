import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/media_repository.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:photo_manager/photo_manager.dart';

Album _album(String name, int count, {int? newestDay}) => Album(
  id: name,
  name: name,
  count: count,
  path: AssetPathEntity(id: name, name: name),
  cover: newestDay == null
      ? null
      : AssetEntity(
          id: '$name-cover',
          typeInt: 1,
          width: 1,
          height: 1,
          createDateSecond:
              DateTime(2026, 11, newestDay).millisecondsSinceEpoch ~/ 1000,
        ),
);

void main() {
  final List<Album> albums = <Album>[
    _album('WhatsApp Images', 266, newestDay: 8),
    _album('camera', 30, newestDay: 10),
    _album('2024', 1, newestDay: 2),
    _album('Empty covers', 5),
  ];

  List<String> names(AlbumsOrder o) =>
      o.apply(albums).map((Album a) => a.name).toList();

  test('the standard order puts the album with the newest photo first', () {
    expect(names(AlbumsOrder.standard), <String>[
      'camera',
      'WhatsApp Images',
      '2024',
      'Empty covers',
    ]);
  });

  test('name sorts A to Z ignoring case, or Z to A', () {
    expect(names(const AlbumsOrder(AlbumsOrderBy.name)), <String>[
      '2024',
      'camera',
      'Empty covers',
      'WhatsApp Images',
    ]);
    expect(
      names(const AlbumsOrder(AlbumsOrderBy.name, reversed: true)).first,
      'WhatsApp Images',
    );
  });

  test('number of items sorts the fullest album first', () {
    expect(names(const AlbumsOrder(AlbumsOrderBy.count)), <String>[
      'WhatsApp Images',
      'camera',
      'Empty covers',
      '2024',
    ]);
  });

  test('an order survives being saved and read back', () {
    const AlbumsOrder o = AlbumsOrder(AlbumsOrderBy.count, reversed: true);
    final AlbumsOrder back = AlbumsOrder.decode(o.encode());
    expect(back.by, AlbumsOrderBy.count);
    expect(back.reversed, isTrue);
    expect(AlbumsOrder.decode('nonsense').by, AlbumsOrderBy.recent);
  });
}
