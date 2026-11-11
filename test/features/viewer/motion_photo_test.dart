import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/viewer/presentation/motion_photo.dart';
import 'package:photo_manager/photo_manager.dart';

final AssetEntity _photo = AssetEntity(
  id: '1',
  typeInt: 1,
  width: 4,
  height: 3,
);

void main() {
  Future<void> open(WidgetTester tester, {required bool motion}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            isMotionPhotoProvider(
              _photo,
            ).overrideWith((Ref ref) async => motion),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  MotionPhoto(asset: _photo, child: const Text('still')),
                  MotionBadge(asset: _photo),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets('a Motion Photo carries the badge', (WidgetTester tester) async {
    await open(tester, motion: true);
    await tester.pumpAndSettle();
    expect(find.text('MOTION'), findsOneWidget);
    expect(find.text('still'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Press and hold the photo')),
      findsOneWidget,
    );
  });

  testWidgets('a plain photo has no badge and ignores a hold', (
    WidgetTester tester,
  ) async {
    await open(tester, motion: false);
    await tester.pumpAndSettle();
    expect(find.text('MOTION'), findsNothing);
    await tester.longPress(find.text('still'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('still'), findsOneWidget);
  });
}
