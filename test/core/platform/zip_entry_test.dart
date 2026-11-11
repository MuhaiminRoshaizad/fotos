import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/platform/native_channel.dart';
import 'package:fotos/core/format/natural_sort.dart';

void main() {
  test('ZipEntry.fromMap reads the fields the channel sends', () {
    final ZipEntry e = ZipEntry.fromMap(<Object?, Object?>{
      'name': 'chapter 1/010.jpg',
      'size': 123456,
      'isImage': true,
    });
    expect(e.name, 'chapter 1/010.jpg');
    expect(e.size, 123456);
    expect(e.isImage, isTrue);
  });

  test('entries sort into reading order by natural name', () {
    final List<ZipEntry> entries = <ZipEntry>[
      ZipEntry.fromMap(<Object?, Object?>{'name': '10.jpg', 'size': 1, 'isImage': true}),
      ZipEntry.fromMap(<Object?, Object?>{'name': '2.jpg', 'size': 1, 'isImage': true}),
      ZipEntry.fromMap(<Object?, Object?>{'name': '1.jpg', 'size': 1, 'isImage': true}),
    ]..sort((ZipEntry a, ZipEntry b) => naturalCompare(a.name, b.name));
    expect(
      entries.map((ZipEntry e) => e.name),
      <String>['1.jpg', '2.jpg', '10.jpg'],
    );
  });
}
