import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/platform/native_channel.dart';
import 'package:fotos/features/albums/presentation/albums_providers.dart';
import 'package:fotos/features/files/presentation/files_screen.dart';

class _FakeNative extends NativeChannel {
  _FakeNative();
  int settingsOpened = 0;

  @override
  Future<bool> hasAllFilesAccess() async => false;

  @override
  Future<String> storageRoot() async => '/storage/emulated/0';

  @override
  Future<void> openAllFilesAccessSettings() async => settingsOpened++;
}

void main() {
  testWidgets('without All files access, Files explains and opens settings', (
    WidgetTester tester,
  ) async {
    final _FakeNative native = _FakeNative();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [nativeChannelProvider.overrideWithValue(native)],
        child: const MaterialApp(home: FilesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('See every file on your phone'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    expect(native.settingsOpened, 1);
  });
}
