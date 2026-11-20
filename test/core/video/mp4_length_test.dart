import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/video/mp4_length.dart';

/// A box: size, type, then [body].
List<int> box(String type, List<int> body) => <int>[
  ..._u32(8 + body.length),
  ...type.codeUnits,
  ...body,
];

/// A full box: version and 24-bit flags before [body].
List<int> full(String type, List<int> body, {int version = 0, int flags = 0}) =>
    box(type, <int>[version, ...(_u32(flags).sublist(1)), ...body]);

List<int> _u32(int v) =>
    (ByteData(4)..setUint32(0, v)).buffer.asUint8List().toList();
List<int> _u64(int v) =>
    (ByteData(8)..setUint64(0, v)).buffer.asUint8List().toList();

List<int> mvhd(int scale, int length) => full('mvhd', <int>[
  ..._u32(0),
  ..._u32(0),
  ..._u32(scale),
  ..._u32(length),
  ...List<int>.filled(80, 0),
]);

List<int> trak(int id, int scale) => box('trak', <int>[
  ...full('tkhd', <int>[
    ..._u32(0),
    ..._u32(0),
    ..._u32(id),
    ...List<int>.filled(68, 0),
  ]),
  ...box(
    'mdia',
    full('mdhd', <int>[
      ..._u32(0),
      ..._u32(0),
      ..._u32(scale),
      ..._u32(0),
      0,
      0,
      0,
      0,
    ]),
  ),
]);

List<int> trex(int id, int duration) => full('trex', <int>[
  ..._u32(id),
  ..._u32(1),
  ..._u32(duration),
  ..._u32(0),
  ..._u32(0),
]);

/// A fragment of [track]: [count] samples starting at [start], each
/// [each] long, or with the lengths in [durations].
List<int> moof(
  int track, {
  int? start,
  int count = 0,
  int? each,
  List<int>? durations,
}) => box(
  'moof',
  box('traf', <int>[
    ...full('tfhd', <int>[
      ..._u32(track),
      if (each != null) ..._u32(each),
    ], flags: each != null ? 0x08 : 0),
    if (start != null) ...full('tfdt', _u64(start), version: 1),
    ...full('trun', <int>[
      ..._u32(durations?.length ?? count),
      ..._u32(0), // data offset
      for (final int d in durations ?? const <int>[]) ..._u32(d),
    ], flags: 0x01 | (durations != null ? 0x100 : 0)),
  ]),
);

List<int> mdat(int bytes) => box('mdat', List<int>.filled(bytes, 7));

Future<Duration?> lengthOf(List<int> bytes) async {
  final Directory dir = await Directory.systemTemp.createTemp('mp4');
  addTearDown(() => dir.delete(recursive: true));
  final File f = File('${dir.path}/v.mp4')..writeAsBytesSync(bytes);
  final RandomAccessFile r = await f.open();
  addTearDown(r.close);
  return mp4Length(r);
}

void main() {
  final List<int> ftyp = box(
    'ftyp',
    'isom'.codeUnits + _u32(0) + 'isomiso6'.codeUnits,
  );

  test('an ordinary MP4 has its length in the header', () async {
    expect(
      await lengthOf(<int>[
        ...ftyp,
        ...box('moov', <int>[...mvhd(1000, 14267), ...trak(1, 90000)]),
        ...mdat(64),
      ]),
      const Duration(milliseconds: 14267),
    );
  });

  test(
    'a fragmented MP4, whose header says 0, adds up its fragments',
    () async {
      final List<int> moov = box('moov', <int>[
        ...mvhd(1000, 0),
        ...trak(1, 1000),
        ...box('mvex', trex(1, 0)),
      ]);
      expect(
        await lengthOf(<int>[
          ...ftyp,
          ...moov,
          ...moof(1, start: 0, count: 25, each: 40),
          ...mdat(500),
          ...moof(1, start: 1000, durations: <int>[30, 30]),
          ...mdat(100),
        ]),
        const Duration(milliseconds: 1060),
      );
    },
  );

  test('without decode times, fragments follow on from each other, and a '
      "track's default length comes from trex", () async {
    final List<int> moov = box('moov', <int>[
      ...mvhd(1000, 0),
      ...trak(1, 30),
      ...box('mvex', trex(1, 1)),
    ]);
    // 30 frames a second: 45 then 45 frames is 3 seconds.
    expect(
      await lengthOf(<int>[
        ...ftyp,
        ...moov,
        ...moof(1, count: 45),
        ...mdat(10),
        ...moof(1, count: 45),
      ]),
      const Duration(seconds: 3),
    );
  });

  test('the longest track sets the length', () async {
    final List<int> moov = box('moov', <int>[
      ...mvhd(1000, 0),
      ...trak(1, 1000),
      ...trak(2, 44100),
      ...box('mvex', <int>[...trex(1, 0), ...trex(2, 0)]),
    ]);
    expect(
      await lengthOf(<int>[
        ...ftyp,
        ...moov,
        ...moof(1, start: 0, count: 10, each: 100),
        ...moof(2, start: 0, count: 2, each: 44100),
      ]),
      const Duration(seconds: 2),
    );
  });

  test('a written whole-movie length (mehd) is used as it is', () async {
    final List<int> moov = box('moov', <int>[
      ...mvhd(1000, 0),
      ...trak(1, 1000),
      ...box('mvex', <int>[...full('mehd', _u32(5000)), ...trex(1, 0)]),
    ]);
    expect(await lengthOf(<int>[...ftyp, ...moov]), const Duration(seconds: 5));
  });

  test('anything that is not an MP4 has no length', () async {
    expect(await lengthOf(<int>[]), isNull);
    expect(await lengthOf(List<int>.generate(300, (int i) => i % 251)), isNull);
  });

  test('a box cut short keeps what was read before it', () async {
    final List<int> moov = box('moov', <int>[
      ...mvhd(1000, 0),
      ...trak(1, 1000),
      ...box('mvex', trex(1, 0)),
    ]);
    final List<int> whole = <int>[
      ...ftyp,
      ...moov,
      ...moof(1, start: 0, count: 5, each: 200),
    ];
    // A last fragment whose trun claims more samples than it holds.
    final List<int> broken = box(
      'moof',
      box('traf', <int>[
        ...full('tfhd', _u32(1)),
        ...full('trun', _u32(1000000), flags: 0x100),
      ]),
    );
    expect(
      await lengthOf(<int>[...whole, ...broken]),
      const Duration(seconds: 1),
    );
  });
}
