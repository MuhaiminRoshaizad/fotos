import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/core/media/media_repository.dart';

import '../support/fake_media_repository.dart';

/// Android 14+ scales fonts non-linearly: small text grows by the full
/// factor, large text much less. A linear scaler can't reproduce that.
class _DampedScaler extends TextScaler {
  const _DampedScaler(this.factor);
  final double factor;

  @override
  double scale(double fontSize) {
    if (fontSize <= 14) return fontSize * factor;
    final double damped = 1 + (factor - 1) * (14 / fontSize);
    return fontSize * damped;
  }

  @override
  double get textScaleFactor => factor;

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) => _DampedScaler(factor.clamp(minScaleFactor, maxScaleFactor));
}

Future<void> _pumpAt(WidgetTester tester, Size size, MediaAccess access) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(bottom: 48 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        mediaRepositoryProvider.overrideWithValue(
          FakeMediaRepository(accessState: access),
        ),
      ],
      child: Builder(
        builder: (BuildContext context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const _DampedScaler(2)),
          child: const FotosApp(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final MediaAccess access in <MediaAccess>[
    MediaAccess.denied,
    MediaAccess.limited,
    MediaAccess.full,
  ]) {
    testWidgets('at 200% text on a small phone nothing overflows ($access)', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, const Size(360, 640), access);
      expect(tester.takeException(), isNull);
      for (final String tab in <String>['Videos', 'Albums', 'Files']) {
        await tester.tap(find.bySemanticsLabel(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  }
}
