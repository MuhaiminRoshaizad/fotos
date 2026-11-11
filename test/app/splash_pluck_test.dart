import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/splash_pluck.dart';

/// Counts how many times its state is created.
class _Probe extends StatefulWidget {
  const _Probe();

  static int created = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.created++;
  }

  @override
  Widget build(BuildContext context) => const Text('app');
}

void main() {
  testWidgets('the app underneath is not rebuilt when the flower goes', (
    WidgetTester tester,
  ) async {
    _Probe.created = 0;
    // Android's launch screen answers that it has gone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('my.minned.fotos/native'),
          (MethodCall call) async => null,
        );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SplashPluck(child: _Probe())),
      ),
    );
    await tester.pumpAndSettle();
    // The petals have been plucked and the flower is gone.
    expect(
      find.descendant(
        of: find.byType(SplashPluck),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );

    expect(find.text('app'), findsOneWidget);
    // Created once: rebuilding it lost a photo opened from another app.
    expect(_Probe.created, 1);
  });

  testWidgets('opened to show a photo, the flower goes at once', (
    WidgetTester tester,
  ) async {
    // Android answers that fotos was started to show one photo.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('my.minned.fotos/native'),
          (MethodCall call) async => call.method == 'awaitSplash' ? true : null,
        );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SplashPluck(child: _Probe())),
      ),
    );
    await tester.pump();
    await tester.pump();
    // Gone within two frames, with no plucking animation left to run.
    expect(
      find.descendant(
        of: find.byType(SplashPluck),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });
}
