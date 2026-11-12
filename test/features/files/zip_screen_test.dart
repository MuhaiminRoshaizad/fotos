import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/platform/native_channel.dart';
import 'package:fotos/core/selection/selection.dart';
import 'package:fotos/core/theme/app_theme.dart';
import 'package:fotos/core/widgets/large_title_scaffold.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:fotos/features/files/presentation/zip_screen.dart';

const String _zip = '/root/Download/Moonlit Harbor Vol. 03.cbz';

ZipEntry _page(String name) => ZipEntry(name: name, size: 1000, isImage: true);

void main() {
  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('my.minned.fotos/native'),
          (MethodCall call) async {
            calls.add(call);
            return call.method == 'zipRemove' ? 1 : null;
          },
        );
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    late ProviderContainer c;
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Out of order on purpose: the screen reads them as pages.
          zipEntriesProvider(_zip).overrideWith(
            (Ref ref) async => <ZipEntry>[
              _page('10.jpg'),
              _page('2.jpg'),
              _page('1.jpg'),
            ],
          ),
          zipPageThumbProvider.overrideWith(
            (Ref ref, (String, String, int) key) async => null as Uint8List?,
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          // Pushed, as from Files, so the page has somewhere to go back to.
          home: Builder(
            builder: (BuildContext context) {
              c = ProviderScope.containerOf(context);
              return Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ZipScreen(path: _zip),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('a ZIP opens as a large-title page of its pages in reading '
      'order, and a tapped page opens large', (WidgetTester tester) async {
    await open(tester);
    expect(find.byType(LargeTitleScaffold), findsOneWidget);
    expect(find.text('3 pages · 3 KB'), findsOneWidget);
    // Reading order, left to right: 1, 2, then 10.
    double x(String name) => tester.getTopLeft(find.bySemanticsLabel(name)).dx;
    expect(x('Page 1.jpg'), lessThan(x('Page 2.jpg')));
    expect(x('Page 2.jpg'), lessThan(x('Page 10.jpg')));

    await tester.tap(find.bySemanticsLabel('Page 2.jpg'));
    await tester.pumpAndSettle();
    expect(find.text('2.jpg · 2 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('2.jpg · 2 of 3'), findsNothing);
  });

  testWidgets('selected pages are deleted through the shared select bar, '
      'after a confirmation', (WidgetTester tester) async {
    final ProviderContainer c = await open(tester);
    await tester.tap(find.text('Select'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Page 1.jpg'));
    await tester.tap(find.bySemanticsLabel('Page 10.jpg'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    final SelectionState sel = c.read(selectionProvider);
    final SelectionAction delete = sel.actions.single;
    expect(delete.label, 'Delete');
    final Future<void> run = delete.run(
      tester.element(find.byType(ZipScreen)),
      sel.ids,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    // The progress dialog's bar keeps moving until the work is done, so
    // step through time, letting Android's reply arrive between steps,
    // rather than wait for everything to settle.
    bool finished = false;
    run.then((_) => finished = true);
    for (int i = 0; i < 60 && !finished; i++) {
      await tester.idle();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finished, isTrue);

    final MethodCall remove = calls.singleWhere(
      (MethodCall m) => m.method == 'zipRemove',
    );
    expect(
      (remove.arguments as Map<Object?, Object?>)['names'],
      unorderedEquals(<String>['1.jpg', '10.jpg']),
    );
    // Done, so select mode ends.
    expect(c.read(selectionProvider).isActiveFor('zip:$_zip'), isFalse);
  });
}
