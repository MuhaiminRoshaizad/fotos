import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Dart file under lib, as (path with / separators, source).
List<(String, String)> _sources() => <(String, String)>[
  for (final FileSystemEntity f in Directory('lib').listSync(recursive: true))
    if (f is File && f.path.endsWith('.dart'))
      (f.path.replaceAll(r'\', '/'), f.readAsStringSync()),
];

/// Files whose source matches [pattern], other than those ending in one of
/// [allowedIn].
List<String> _offenders(
  Pattern pattern, {
  List<String> allowedIn = const <String>[],
}) => <String>[
  for (final (String path, String source) in _sources())
    if (!allowedIn.any(path.endsWith) && source.contains(pattern)) path,
];

void main() {
  test('bottom sheets open only through showAppSheet', () {
    // showModalBottomSheet draws under the system navigation bar; the helper
    // adds the bottom SafeArea every sheet needs.
    expect(
      _offenders(
        'showModalBottomSheet',
        allowedIn: <String>['core/widgets/app_sheet.dart'],
      ),
      isEmpty,
    );
  });

  test('icons come from CupertinoIcons, never Material Icons', () {
    expect(_offenders(RegExp(r'(?<!Cupertino)\bIcons\.')), isEmpty);
  });

  test('haptics go through AppHaptics', () {
    expect(
      _offenders(
        'HapticFeedback',
        allowedIn: <String>['core/haptics/app_haptics.dart'],
      ),
      isEmpty,
    );
  });

  test('pages and dialogs use the iOS pieces, not Material ones', () {
    // LargeTitleScaffold or ViewerTopBar instead of an app bar; a Cupertino
    // dialog or runBatch instead of a Material one.
    expect(
      _offenders(
        RegExp(r'\b(AppBar|SliverAppBar|AlertDialog)\(|\bshowDialog\b'),
      ),
      isEmpty,
    );
  });

  test('notifier classes end in Notifier', () {
    final RegExp notifier = RegExp(
      r'class (\w+) extends (?:Async|Stream)?Notifier<',
    );
    expect(<String>[
      for (final (String path, String source) in _sources())
        for (final RegExpMatch m in notifier.allMatches(source))
          if (!m.group(1)!.endsWith('Notifier')) '$path: ${m.group(1)}',
    ], isEmpty);
  });
}
