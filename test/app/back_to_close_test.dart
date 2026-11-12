import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/app/floating_nav.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/widgets/toast.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fake_media_repository.dart';

void main() {
  int closes = 0;
  final List<bool> handlesBack = <bool>[];

  setUp(() {
    closes = 0;
    handlesBack.clear();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'SystemNavigator.pop') closes++;
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            handlesBack.add(call.arguments as bool);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  int tab(WidgetTester tester) =>
      tester.widget<FloatingNav>(find.byType(FloatingNav)).index;

  testWidgets('Back on another tab goes to the first; on the first it asks '
      'once, and a second Back closes fotos', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Albums').last);
    await tester.pumpAndSettle();
    expect(tab(tester), 2);

    await back(tester);
    expect(tab(tester), 0);
    expect(find.text('Press back again to close fotos'), findsNothing);
    expect(closes, 0);

    await back(tester);
    expect(find.text('Press back again to close fotos'), findsOneWidget);
    // A hint, not a success: no icon at all.
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsNothing);
    expect(find.byIcon(CupertinoIcons.info_circle), findsNothing);
    expect(closes, 0);

    await back(tester);
    expect(closes, 1);
    await tester.pumpAndSettle();
  });

  Future<void> openOnPhotos(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  const String hint = 'Press back again to close fotos';

  testWidgets('the hint shows for 2 s with a draining bar; once it has gone, '
      'Back asks again, every time', (WidgetTester tester) async {
    await openOnPhotos(tester);
    for (int round = 0; round < 3; round++) {
      await back(tester);
      expect(find.text(hint), findsOneWidget, reason: 'round $round');
      // Still armed just before the 2 s are up.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text(hint), findsOneWidget);
      // Gone after them.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
    }
    expect(closes, 0);
  });

  testWidgets('another message replacing the hint disarms it', (
    WidgetTester tester,
  ) async {
    await openOnPhotos(tester);
    await back(tester);
    expect(find.text(hint), findsOneWidget);
    showToast(tester.element(find.byType(FloatingNav)), 'Moved 3 items');
    await tester.pump();
    await back(tester);
    expect(closes, 0);
    expect(find.text(hint), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('opening another tab while the hint shows takes it down', (
    WidgetTester tester,
  ) async {
    await openOnPhotos(tester);
    await back(tester);
    expect(find.text(hint), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Files').last);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    // Back from Files goes to Photos, then asks again rather than closing.
    await back(tester);
    expect(tab(tester), 0);
    await back(tester);
    expect(closes, 0);
    expect(find.text(hint), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('on a tab, fotos tells Android it handles Back, so Android '
      'asks before closing it', (WidgetTester tester) async {
    // On Android 14 and later the app says in advance whether it handles
    // Back; if it says no, Android closes it without asking. That signal is
    // only sent once the app is resumed.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(handlesBack, isNotEmpty);
    expect(handlesBack.last, isTrue);

    await tester.tap(find.bySemanticsLabel('Files').last);
    await tester.pumpAndSettle();
    expect(handlesBack.last, isTrue);
  });
}
