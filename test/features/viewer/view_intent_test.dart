import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/app/app.dart';
import 'package:fotos/core/media/empty_albums.dart';
import 'package:fotos/core/media/media_providers.dart';
import 'package:fotos/features/albums/data/album_prefs.dart';
import 'package:fotos/features/viewer/presentation/view_intent_handler.dart';

import '../../support/fake_media_repository.dart';

class _NoEmpty extends EmptyAlbumsNotifier {
  @override
  Future<List<String>> build() async => const <String>[];
}

class _NoPrefs extends AlbumPrefsNotifier {
  @override
  Future<AlbumPrefs> build() async => const AlbumPrefs();
}

void main() {
  test('reads the MediaStore id from content://media addresses only', () {
    expect(mediaStoreId('content://media/external/images/media/1234'), '1234');
    expect(
      mediaStoreId('content://media/external_primary/video/media/77'),
      '77',
    );
    expect(
      mediaStoreId('content://com.other.app.provider/files/a.jpg'),
      isNull,
    );
    expect(mediaStoreId('file:///storage/emulated/0/DCIM/a.jpg'), isNull);
    expect(mediaStoreId('content://media/external/images/media'), isNull);
  });

  testWidgets('a file from outside the library is turned away with a toast', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          emptyAlbumsProvider.overrideWith(_NoEmpty.new),
          albumPrefsProvider.overrideWith(_NoPrefs.new),
        ],
        child: const FotosApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Another app's "View" while fotos is running.
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'my.minned.fotos/native',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('openUri', 'file:///storage/emulated/0/a.txt'),
          ),
          (_) {},
        );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'fotos opens photos and videos from this phone\'s library only.',
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}
