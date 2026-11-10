import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/core/widgets/app_sheet.dart';
import 'package:fotos/core/widgets/inset_group.dart';

void main() {
  Color rowColor(WidgetTester tester) => tester
      .widget<Material>(
        find
            .ancestor(of: find.text('Row'), matching: find.byType(Material))
            .first,
      )
      .color!;

  testWidgets('rows on a dark sheet are lighter than the sheet', (
    WidgetTester tester,
  ) async {
    final ThemeData theme = buildAppTheme(Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (_) => const InsetGroup(
                  children: <Widget>[GroupRow(title: 'Row')],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(rowColor(tester), theme.colorScheme.surfaceContainerHigh);
    expect(
      rowColor(tester),
      isNot(theme.bottomSheetTheme.backgroundColor),
      reason: 'rows the colour of the sheet cannot be seen',
    );
  });

  testWidgets('rows on a dark page keep the grouped row colour', (
    WidgetTester tester,
  ) async {
    final ThemeData theme = buildAppTheme(Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: InsetGroup(children: <Widget>[GroupRow(title: 'Row')]),
        ),
      ),
    );

    expect(rowColor(tester), theme.colorScheme.groupedRow);
  });
}
