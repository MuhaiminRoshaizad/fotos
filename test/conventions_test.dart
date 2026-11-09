import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bottom sheets open only through showAppSheet', () {
    // showModalBottomSheet draws under the system navigation bar; the helper
    // adds the bottom SafeArea every sheet needs.
    final List<String> offenders = <String>[
      for (final FileSystemEntity f in Directory(
        'lib',
      ).listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path
                .replaceAll(r'\', '/')
                .endsWith('core/widgets/app_sheet.dart') &&
            f.readAsStringSync().contains('showModalBottomSheet'))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
