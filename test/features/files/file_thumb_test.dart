import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/presentation/file_thumb.dart';

void main() {
  const MethodChannel channel = MethodChannel('my.minned.fotos/native');
  final List<String> asked = <String>[];

  setUp(() {
    asked.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'thumbnail') {
            asked.add(
              (call.arguments as Map<Object?, Object?>)['path']! as String,
            );
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Widget thumb(String path) => ProviderScope(
    child: MaterialApp(
      home: FileThumb(path: path, px: 400, placeholder: const Text('glyph')),
    ),
  );

  testWidgets('a tile flung past never asks for its thumbnail', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(thumb('/s/IMG_6160.JPG'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    expect(asked, isEmpty);
  });

  testWidgets('a tile that stays on screen asks once, showing its glyph '
      'meanwhile', (WidgetTester tester) async {
    await tester.pumpWidget(thumb('/s/IMG_6161.JPG'));
    expect(find.text('glyph'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(asked, <String>['/s/IMG_6161.JPG']);
    await tester.pumpWidget(const SizedBox());
  });
}
