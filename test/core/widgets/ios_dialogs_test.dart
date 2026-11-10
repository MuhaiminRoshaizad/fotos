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
