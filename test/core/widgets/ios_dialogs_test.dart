import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/core/widgets/app_sheet.dart';
import 'package:fotos/core/widgets/dialogs.dart';

Future<BuildContext> _host(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.dark),
      home: Builder(
        builder: (BuildContext c) {
          ctx = c;
          return const Scaffold();
        },
      ),
    ),
  );
  return ctx;
}

void main() {
  _nameSheetTests();
  testWidgets('an action sheet returns the choice, and null on Cancel', (
    WidgetTester tester,
  ) async {
    final BuildContext ctx = await _host(tester);
    Future<String?> open() => showActionSheet<String>(
      ctx,
      title: 'Holiday',
      choices: const <SheetChoice<String>>[
        SheetChoice<String>('pin', 'Pin to top'),
        SheetChoice<String>('delete', 'Delete album', destructive: true),
      ],
    );

    Future<String?> result = open();
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('Delete album'));
    await tester.pumpAndSettle();
    expect(await result, 'delete');

    result = open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('a destructive confirm is an iOS alert with Cancel bold', (
    WidgetTester tester,
  ) async {
    final BuildContext ctx = await _host(tester);
    final Future<bool> ok = confirmAction(
      ctx,
      title: 'Delete folder?',
      message: 'This can\'t be undone.',
      confirmLabel: 'Delete',
    );
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    final List<CupertinoDialogAction> actions = tester
        .widgetList<CupertinoDialogAction>(find.byType(CupertinoDialogAction))
        .toList();
    expect(actions.first.isDefaultAction, isTrue);
    expect(actions.last.isDestructiveAction, isTrue);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await ok, isTrue);
  });
}

void _nameSheetTests() {
  testWidgets('a long file name wraps in the rename sheet and keeps its '
      'ending', (WidgetTester tester) async {
    final BuildContext ctx = await _host(tester);
    const String long =
        'Moonlit Harbor Chronicles Vol. 03 (2024) (Digital) (Kuro-Scans).cbz';
    final Future<String?> result = promptName(
      ctx,
      title: 'Rename file',
      label: 'File name',
      hint: 'File name',
      confirmLabel: 'Rename',
      initial: long,
      selectStem: true,
      validate: (String v) => v.isEmpty ? 'Enter a name' : null,
    );
    await tester.pumpAndSettle();
    final EditableText field = tester.widget(find.byType(EditableText));
    // Only the name is edited; the ending sits after it, kept.
    expect(field.controller.text, long.substring(0, long.length - 4));
    expect(find.text('.cbz'), findsOneWidget);
    // The whole name shows: it wraps instead of scrolling sideways.
    expect(tester.getSize(find.byType(EditableText)).height, greaterThan(30));

    await tester.enterText(find.byType(EditableText), 'Moonlit Vol. 03');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    expect(await result, 'Moonlit Vol. 03.cbz');
  });

  testWidgets('a name sheet stays above the keyboard', (
    WidgetTester tester,
  ) async {
    final BuildContext ctx = await _host(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    promptName(
      ctx,
      title: 'New album',
      label: 'Album name',
      hint: 'e.g. Holiday 2026',
      confirmLabel: 'Create',
      validate: (_) => null,
    );
    await tester.pumpAndSettle();
    final double keyboardTop =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        900 / tester.view.devicePixelRatio;
    expect(
      tester.getBottomLeft(find.byType(EditableText)).dy,
      lessThan(keyboardTop),
    );
  });
}
