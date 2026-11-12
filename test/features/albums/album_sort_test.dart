import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity _a(String id, String title, int seconds) => AssetEntity(
  id: id,
  typeInt: 2,
  width: 1,
  height: 1,
  duration: seconds,
  title: title,
);

void main() {
  final List<AssetEntity> newestFirst = <AssetEntity>[
    _a('1', 'beach.mp4', 30),
    _a('2', 'Alley.mp4', 90),
    _a('3', 'cake.mp4', 5),
  ];

  List<String> ids(AlbumSort s) =>
      s.apply(newestFirst).map((AssetEntity e) => e.id).toList();

  test('date taken keeps the library order, or reverses it', () {
    expect(ids(AlbumSort.standard), <String>['1', '2', '3']);
    expect(ids(const AlbumSort(AlbumSortBy.taken, reversed: true)), <String>[
      '3',
      '2',
      '1',
    ]);
  });

  test('name sorts A to Z ignoring case', () {
    expect(ids(const AlbumSort(AlbumSortBy.name)), <String>['2', '1', '3']);
  });

  test('name sorts page numbers naturally, not as text', () {
    final List<AssetEntity> pages = <AssetEntity>[
      _a('p10', '10.jpg', 1),
      _a('p2', '2.jpg', 1),
      _a('p1', '1.jpg', 1),
    ];
    final List<String> order = const AlbumSort(
      AlbumSortBy.name,
    ).apply(pages).map((AssetEntity e) => e.id).toList();
    expect(order, <String>['p1', 'p2', 'p10']);
  });

  test('length sorts longest first by default', () {
    expect(ids(const AlbumSort(AlbumSortBy.length)), <String>['2', '1', '3']);
  });

  test('encode and decode round-trip, unknown values fall back', () {
    const AlbumSort s = AlbumSort(AlbumSortBy.name, reversed: true);
    final AlbumSort back = AlbumSort.decode(s.encode());
    expect(back.by, AlbumSortBy.name);
    expect(back.reversed, isTrue);
    expect(AlbumSort.decode('nonsense').by, AlbumSortBy.taken);
  });

  test('only date order groups by date', () {
    expect(AlbumSort.standard.groupsByDate, isTrue);
    expect(const AlbumSort(AlbumSortBy.name).groupsByDate, isFalse);
  });
}
