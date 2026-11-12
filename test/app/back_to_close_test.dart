import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/app/floating_nav.dart';
import 'package:fotos/core/media/media_providers.dart';
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
    // A hint, not a success: no tick.
    expect(find.byIcon(CupertinoIcons.info_circle), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsNothing);
    expect(closes, 0);

    await back(tester);
    expect(closes, 1);

    // Once the toast has gone, Back asks again rather than closing.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await back(tester);
    expect(closes, 1);
    expect(find.text('Press back again to close fotos'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
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
