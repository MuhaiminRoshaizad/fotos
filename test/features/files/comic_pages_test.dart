import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/domain/file_entry.dart';
import 'package:fotos/features/files/presentation/file_row.dart';
import 'package:fotos/features/files/presentation/file_tile.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';

FileEntry _zip(String name) => FileEntry(
  path: '/root/$name',
  name: name,
  kind: kindOf(name, isDirectory: false),
  size: 3200000,
  modified: DateTime(2026, 11, 14),
);

/// Page counts as Android gives them: a comic has one, other ZIPs none.
final Map<String, int?> _pages = <String, int?>{
  '/root/Iron Orchard 03.cbz': 187,
  '/root/Moonlit Harbor Vol. 02.zip': 24,
  '/root/takeout-sample.zip': null,
};

Widget _app(Widget child) => ProviderScope(
  overrides: [
    zipPagesProvider.overrideWith(
      (Ref ref, (String, int) zip) async => _pages[zip.$1],
    ),
    zipCoverProvider.overrideWith(
      (Ref ref, (String, int) zip) async => null as Uint8List?,
    ),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('a comic tile shows its page count, .zip or .cbz alike, and '
      'a ZIP that is not a comic shows none', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        Row(
          children: <Widget>[
            for (final String name in _pages.keys.map(
              (String p) => p.split('/').last,
            ))
              SizedBox(
                width: 120,
                child: FileTile(
                  entry: _zip(name),
                  onTap: () {},
                  onLongPress: () {},
                  onMore: () {},
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('187'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    // Only the two comics carry a badge.
    expect(find.byIcon(CupertinoIcons.book_fill), findsNWidgets(2));
  });

  testWidgets('a comic row leads its details with the page count', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Column(
          children: <Widget>[
            for (final String name in <String>[
              'Iron Orchard 03.cbz',
              'takeout-sample.zip',
            ])
              FileRow(
                entry: _zip(name),
                onTap: () {},
                onLongPress: () {},
                onMore: () {},
                onDelete: () {},
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('187 pages · 3.2 MB'), findsOneWidget);
    expect(find.textContaining('pages'), findsOneWidget);
  });
}
