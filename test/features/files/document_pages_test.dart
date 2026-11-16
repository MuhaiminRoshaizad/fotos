import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/core/widgets/large_title_scaffold.dart';
import 'package:fotos/features/files/presentation/pdf_screen.dart';
import 'package:fotos/features/files/presentation/text_screen.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('my.minned.fotos/native'),
          (MethodCall call) async => switch (call.method) {
            'pdfPageCount' => 2,
            // No picture: the page keeps its place and says so.
            _ => throw PlatformException(code: 'none'),
          },
        );
  });

  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          // Pushed, as from a folder in Files.
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => page)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a PDF opens as a large-title page with a back button named '
      'after its folder and Share in the bar', (WidgetTester tester) async {
    await open(tester, const PdfScreen(path: '/root/Download/Report.pdf'));
    expect(find.byType(LargeTitleScaffold), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Download'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 1'), findsOneWidget);
  });

  testWidgets('a text file opens as a large-title page, read once however '
      'often the page rebuilds', (WidgetTester tester) async {
    final Directory dir =
        await tester.runAsync(
              () => Directory.systemTemp.createTemp('fotos_text'),
            )
            as Directory;
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File('${dir.path}/Notes.txt');
    await tester.runAsync(() => file.writeAsString('first line\nsecond'));

    await open(tester, TextScreen(path: file.path));
    // The file is read on real IO, outside the test's fake clock.
    for (
      int i = 0;
      i < 50 && find.byType(SelectableText).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(LargeTitleScaffold), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('first line\nsecond'), findsOneWidget);

    // Collapsing the title rebuilds the page; the text stays put.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('first line\nsecond'), findsOneWidget);
  });
}
